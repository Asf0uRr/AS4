# AS4 IR Tool - Quick Scan (optional). ASCII only.
# Points the bundled Hayabusa rules (and optionally Chainsaw/Sigma) at a folder of event logs and answers one question:
# is there anything here that needs attention? Fully local: no downloads, no lookups, nothing leaves the machine.
# Ideas used, all offline: MITRE ATT&CK kill-chain view and incident window (SANS FOR508 "find evil", Mandiant attack lifecycle),
# log-coverage and log-gap checks (blind spots, cleared logs), failed-then-successful logon pattern, rule consensus from a second
# engine, transparent scoring and plain next steps.

$global:QsCfg = $null
$global:QsTactics = [ordered]@{ Recon = 'Reconnaissance'; ResDev = 'Resource Development'; InitAccess = 'Initial Access'; Exec = 'Execution'; Persis = 'Persistence'; PrivEsc = 'Privilege Escalation'; Stealth = 'Defence Evasion'; DefImpair = 'Defence Impairment'; CredAccess = 'Credential Access'; Disc = 'Discovery'; LatMov = 'Lateral Movement'; Collect = 'Collection'; C2 = 'Command and Control'; Exfil = 'Exfiltration'; Impact = 'Impact' }

function Get-QsConfig {
    if ($global:QsCfg) { return $global:QsCfg }
    $sc = Get-Content -LiteralPath (Join-Path $global:P.Profiles 'triage_scoring.json') -Raw | ConvertFrom-Json
    $pb = Get-Content -LiteralPath (Join-Path $global:P.Profiles 'triage_playbook.json') -Raw | ConvertFrom-Json
    $global:QsCfg = [pscustomobject]@{ Scoring = $sc; Playbook = $pb }
    $global:QsCfg
}

function Get-QsLogTypes {
    param([string[]]$Names)
    $pat = [ordered]@{ Security = '(^|[\\/])Security[_.]'; System = '(^|[\\/])System[_.]'; Application = '(^|[\\/])Application[_.]'; PowerShell = 'PowerShell'; Sysmon = 'Sysmon'; Defender = 'Defender'; TerminalServices = 'TerminalServices|RdpCoreTS|RemoteDesktop'; TaskScheduler = 'TaskScheduler'; WinRM = 'WinRM'; WMI = 'WMI-Activity' }
    $have = [ordered]@{}; foreach ($k in $pat.Keys) { $have[$k] = (@($Names | Where-Object { $_ -match $pat[$k] }).Count -gt 0) }
    $have
}

function Find-As4LogDirs {
    # Finds every folder under $Root that holds .evtx files, skipping AS4's own output and filtered copies, and skipping folders that
    # only repeat files (same name and size) already seen, so the same log is not scanned twice.
    param([Parameter(Mandatory)][string]$Root)
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.evtx -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/](00_|11_|12_|13_)[^\\/]*[\\/]' -and $_.FullName -notmatch 'filtered_evtx' })
    $groups = @($files | Group-Object DirectoryName | Sort-Object @{ e = { if ($_.Name -match 'raw_evtx') { 0 } else { 1 } } }, Name)
    $seen = @{}; $out = @()
    foreach ($g in $groups) {
        $new = @($g.Group | Where-Object { -not $seen.ContainsKey("$($_.Name)|$($_.Length)") })
        if (-not $new.Count) { continue }
        foreach ($f in $g.Group) { $seen["$($f.Name)|$($f.Length)"] = 1 }
        $out += [pscustomobject]@{ Dir = $g.Name; Files = $g.Group.Count; Bytes = ($g.Group | Measure-Object Length -Sum).Sum; Names = @($g.Group | ForEach-Object { $_.Name }) }
    }
    $out
}

function ConvertTo-QsDate { param([string]$s) $d = [datetimeoffset]::MinValue; if ($s -and [datetimeoffset]::TryParse($s.Trim(), [Globalization.CultureInfo]::InvariantCulture, 'AssumeUniversal', [ref]$d)) { $d } else { $null } }

function Get-QsCoverage {
    # log-metrics rows from Hayabusa -> what logs exist, how long they cover, signs of gaps or clearing
    param($Rows, [string[]]$Names)
    $types = Get-QsLogTypes $Names
    $files = @(); foreach ($r in $Rows) { $files += [pscustomobject]@{ File = $r.Filename; Events = [int](("$($r.Events)") -replace '[^\d]', ''); First = (ConvertTo-QsDate $r.'First Timestamp'); Last = (ConvertTo-QsDate $r.'Last Timestamp') } }
    $first = @($files | Where-Object First | ForEach-Object { $_.First } | Sort-Object | Select-Object -First 1); $last = @($files | Where-Object Last | ForEach-Object { $_.Last } | Sort-Object -Descending | Select-Object -First 1)
    $flags = @()
    $sec = @($files | Where-Object { $_.File -match '^Security[_.]' -and $_.First }); $sys = @($files | Where-Object { $_.File -match '^System[_.]' -and $_.First })
    if ($sec.Count -and $sys.Count) { $gap = ($sec[0].First - $sys[0].First).TotalDays; if ($gap -gt 14) { $flags += "The Security log starts $([int]$gap) days after the System log. It may have been cleared or rolled over, so older logon activity is missing." } }
    foreach ($f in $files) { if ($f.Events -eq 0) { $flags += "$($f.File) contains no events." } }
    $span = if ($first.Count -and $last.Count) { [math]::Round(($last[0] - $first[0]).TotalDays, 1) } else { $null }
    [pscustomobject]@{ Types = $types; Files = $files; First = $(if ($first.Count) { $first[0] } else { $null }); Last = $(if ($last.Count) { $last[0] } else { $null }); SpanDays = $span; Flags = $flags; FileCount = $files.Count; Events = ($files | Measure-Object Events -Sum).Sum }
}

function Get-QsAnalysis {
    # Pure function: timeline rows + coverage -> verdict, reasons, kill-chain, window, entities, blind spots, next steps.
    param($Rows, $Coverage, $Second)
    $cfg = Get-QsConfig; $sc = $cfg.Scoring; $pb = $cfg.Playbook
    $global:SelfDropped = 0; $Rows = @($Rows | Where-Object { if (Test-As4SelfText ("$($_.RuleTitle) $($_.Details) $($_.ExtraFieldInfo)")) { $global:SelfDropped++; $false } else { $true } }); $selfN = $global:SelfDropped
    $rows = @($Rows | ForEach-Object { $sev = ConvertTo-HaySeverity $_.Level; $t = ConvertTo-QsDate $_.Timestamp; [pscustomobject]@{ T = $t; Time = $_.Timestamp; Sev = $sev; Rank = $global:HaySevRank[$sev]; Title = $_.RuleTitle; Computer = $_.Computer; Channel = $_.Channel; EID = "$($_.EventID)"; Tactics = $_.MitreTactics; Details = $_.Details; Extra = $_.ExtraFieldInfo } })
    $by = [ordered]@{ critical = 0; high = 0; medium = 0; low = 0; info = 0 }; foreach ($g in ($rows | Group-Object Sev)) { $by[$g.Name] = $g.Count }
    # unique rules
    $rules = @($rows | Group-Object Title | ForEach-Object { $g = $_; $top = ($g.Group | Sort-Object Rank -Descending | Select-Object -First 1); $ts = @($g.Group | Where-Object T | ForEach-Object { $_.T } | Sort-Object)
        [pscustomobject]@{ Title = $g.Name; Sev = $top.Sev; Rank = $top.Rank; Count = $g.Count; First = $(if ($ts.Count) { $ts[0] } else { $null }); Last = $(if ($ts.Count) { $ts[-1] } else { $null }); Tactics = $top.Tactics; Sample = $top.Details; Computer = $top.Computer } } | Sort-Object @{ e = 'Rank'; Descending = $true }, @{ e = 'Count'; Descending = $true })
    # score
    $score = 0.0; $reasons = @()
    foreach ($lv in 'critical', 'high', 'medium', 'low') { $cfgL = $sc.Levels.$lv; $pts = 0.0; $ur = @($rules | Where-Object { $_.Sev -eq $lv }); foreach ($u in $ur) { $pts += $cfgL.Weight * (1 + [math]::Log10([math]::Max(1, $u.Count))) }
        $pts = [math]::Min($pts, $cfgL.Cap); $score += $pts; if ($ur.Count -and $lv -in 'critical', 'high') { $reasons += [pscustomobject]@{ Text = "$($ur.Count) $lv rule$(if ($ur.Count -ne 1) { 's' }) matched ($($rows | Where-Object { $_.Sev -eq $lv } | Measure-Object | ForEach-Object Count) events)"; Points = [math]::Round($pts, 1) } } }
    $notLow = @($rules | Where-Object { $_.Rank -ge 2 })
    foreach ($fl in $sc.Flags) { if ($fl.Id -eq 'bruteforce_ok') { continue }
        $hit = @($notLow | Where-Object { $_.Title -match $fl.Pattern } | Select-Object -First 3); if ($hit.Count) { $score += $fl.Points; $reasons += [pscustomobject]@{ Text = "$($fl.Reason) ($(($hit | ForEach-Object { $_.Title }) -join '; '))"; Points = $fl.Points } } }
    # failed-then-successful logons from the same address
    $ipRx = '\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b'
    $fail = @($rows | Where-Object { $_.EID -eq '4625' }); $ok = @($rows | Where-Object { $_.EID -eq '4624' }); $bf = @(); $bfIps = @()
    foreach ($g in ($fail | Where-Object { $_.Details -match $ipRx } | Group-Object { ([regex]::Match($_.Details, $ipRx)).Value } | Where-Object { $_.Count -ge [int]$sc.BruteForce.MinFailures })) {
        if ($g.Name -in '127.0.0.1', '0.0.0.0') { continue }; $lastFail = ($g.Group | Where-Object T | ForEach-Object { $_.T } | Sort-Object | Select-Object -Last 1)
        $win = @($ok | Where-Object { $_.Details -match [regex]::Escape($g.Name) -and $_.T -and $lastFail -and $_.T -ge $lastFail }); if ($win.Count) { $bf += "$($g.Name): $($g.Count) failed logons, then a successful logon"; $bfIps += [pscustomobject]@{ Value = $g.Name; Count = $g.Count } } }
    if ($bf.Count) { $p = ($sc.Flags | Where-Object Id -eq 'bruteforce_ok').Points; $score += $p; $reasons += [pscustomobject]@{ Text = ("A source failed to log on many times and then succeeded: " + ($bf -join '; ')); Points = $p } }
    $score = [math]::Round($score, 0)
    $vd = $sc.Verdicts | Where-Object { $score -le $_.Max } | Select-Object -First 1
    # kill chain
    $chain = @(); foreach ($k in $pb.Order) { $name = $global:QsTactics[$k]; $m = @($rows | Where-Object { $_.Tactics -and (($_.Tactics -split '[\u00a6|,;]\s*' | ForEach-Object { $_.Trim() }) -contains $k) })
        $chain += [pscustomobject]@{ Key = $k; Name = $name; All = $m.Count; Serious = @($m | Where-Object { $_.Rank -ge 4 }).Count } }
    # incident window and histogram
    $serious = @($rows | Where-Object { $_.Rank -ge 4 -and $_.T }); if (-not $serious.Count) { $serious = @($rows | Where-Object { $_.Rank -ge 3 -and $_.T }) }
    $win = $null; $hist = @()
    if ($serious.Count) { $ts = @($serious | ForEach-Object { $_.T } | Sort-Object); $win = [pscustomobject]@{ From = $ts[0]; To = $ts[-1]; Hours = [math]::Round(($ts[-1] - $ts[0]).TotalHours, 1) }
        $daily = (($ts[-1] - $ts[0]).TotalDays -gt 3); $all = @($rows | Where-Object { $_.T -and $_.Rank -ge 2 })
        $fmt = if ($daily) { 'yyyy-MM-dd' } else { 'yyyy-MM-dd HH:00' }
        foreach ($g in ($all | Group-Object { $_.T.UtcDateTime.ToString($fmt) } | Sort-Object Name)) { $hist += [pscustomobject]@{ Label = $g.Name; Serious = @($g.Group | Where-Object { $_.Rank -ge 4 }).Count; Other = @($g.Group | Where-Object { $_.Rank -lt 4 }).Count } } }
    # entities (from low and above, so noise from informational rules does not drown them)
    $use = @($rows | Where-Object { $_.Rank -ge 2 })
    $ipLbl = '(?i)(?:\bIP\w*|Addr\w*|Src\w*|Source\w*|Dest\w*|Client\w*|Remote\w*|Workstation\w*)\s*[:=]\s*()'
    $ips = @($use | ForEach-Object { [regex]::Matches("$($_.Details) $($_.Extra)", $ipLbl) | ForEach-Object { $_.Groups[1].Value } } | Where-Object { $_ -notin '0.0.0.0', '127.0.0.1', '255.255.255.255' } | Group-Object | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ Value = $_.Name; Count = $_.Count } })
    $usrRx = '(?i)\b(?:Target ?User|Subject ?User|User(?:name)?|Account|SrcUser|TgtUser)\w*:\s*([^\u00a6|]+?)\s*(?:\u00a6|\||$)'
    $ips = @(@($bfIps) + @($ips) | Group-Object Value | ForEach-Object { [pscustomobject]@{ Value = $_.Name; Count = ($_.Group | Measure-Object Count -Maximum).Maximum } } | Sort-Object Count -Descending | Select-Object -First 8)
    $users = @($use | ForEach-Object { [regex]::Match("$($_.Details)", $usrRx).Groups[1].Value.Trim() } | Where-Object { $_ -and $_ -notin '-', '(null)', 'SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE' } | Group-Object | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ Value = $_.Name; Count = $_.Count } })
    $hosts = @($use | Where-Object Computer | Group-Object Computer | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ Value = $_.Name; Count = $_.Count } })
    # blind spots
    $blind = @(); if ($selfN) { $blind += "$selfN rule match(es) were caused by AS4 itself (its own commands, scripts or rule files) and were left out of this verdict. The raw timeline still contains them." }; if ($Coverage) { foreach ($k in 'Security', 'System', 'PowerShell', 'Sysmon', 'Defender', 'TerminalServices', 'TaskScheduler') { if (-not $Coverage.Types[$k]) { $blind += $pb.Blind.$k } }
        if ($Coverage.SpanDays -ne $null -and $Coverage.SpanDays -lt 7) { $blind += "The logs cover only $($Coverage.SpanDays) days. Older activity cannot be seen." }; foreach ($f in $Coverage.Flags) { $blind += $f } }
    # next steps
    $next = @($pb.Always); $seenK = @{}
    foreach ($c in $chain) { if ($c.Serious -gt 0 -or ($c.All -gt 0 -and $score -ge 15)) { $t = $pb.Tactics.$($c.Key); if ($t) { foreach ($s in $t.Steps) { if (-not $seenK[$s]) { $seenK[$s] = 1; $next += "$($t.Name): $s" } } } } }
    if ($bf.Count) { $next += 'Credential access: the address that guessed the password may have succeeded. Reset that account and look for other logons from the same address.' }
    [pscustomobject]@{ Score = $score; Verdict = $vd.Name; Color = $vd.Color; VerdictText = $vd.Text; Reasons = $reasons; Counts = $by; Total = $rows.Count; Rules = $rules; Chain = $chain; Window = $win; Hist = $hist; Ips = $ips; Users = $users; Hosts = $hosts; Blind = $blind; Next = ($next | Select-Object -First 10); Second = $Second; Coverage = $Coverage }
}

function Format-QsDate { param($d) if ($d) { ([datetimeoffset]$d).UtcDateTime.ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '-' } }

function New-QsText {
    param($A, $Meta)
    $l = @(); $l += "AS4 IR Tool - Quick Scan"; $l += ("=" * 60)
    $l += "Case: $($Meta.Case)    Scanned: $($Meta.Scanned) UTC    Source: $($Meta.Source)"; $l += "Tools: $($Meta.Tools)"; $l += ''
    $l += "VERDICT: $($A.Verdict)  (score $($A.Score))"; $l += $A.VerdictText; $l += ''
    $l += "Findings: " + (($A.Counts.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', ')
    if ($A.Coverage) { $l += "Logs: $($A.Coverage.FileCount) files, $($A.Coverage.Events) events, $(Format-QsDate $A.Coverage.First) to $(Format-QsDate $A.Coverage.Last)" }
    if ($A.Window) { $l += "Incident window (serious findings): $(Format-QsDate $A.Window.From) to $(Format-QsDate $A.Window.To) ($($A.Window.Hours) h)" }
    $l += ''; $l += 'WHY THIS VERDICT'; foreach ($r in $A.Reasons) { $l += " + $($r.Points)  $($r.Text)" }; if (-not $A.Reasons.Count) { $l += ' (no scoring reasons)' }
    $l += ''; $l += 'ATTACK CHAIN (MITRE ATT&CK tactics seen)'; foreach ($c in $A.Chain) { if ($c.All) { $l += ("  {0,-22} {1,5} findings ({2} serious)" -f $c.Name, $c.All, $c.Serious) } }
    $l += ''; $l += 'TOP FINDINGS'; foreach ($r in ($A.Rules | Select-Object -First 15)) { $l += ("  [{0}] {1}  x{2}  first {3}  last {4}" -f $r.Sev.ToUpper(), $r.Title, $r.Count, (Format-QsDate $r.First), (Format-QsDate $r.Last)) }
    $l += ''; $l += 'MOST INVOLVED'; $l += "  Hosts: " + (($A.Hosts | ForEach-Object { "$($_.Value) ($($_.Count))" }) -join ', '); $l += "  Accounts: " + (($A.Users | ForEach-Object { "$($_.Value) ($($_.Count))" }) -join ', '); $l += "  Addresses: " + (($A.Ips | ForEach-Object { "$($_.Value) ($($_.Count))" }) -join ', ')
    if ($A.Second) { $l += ''; $l += 'SECOND OPINION (Chainsaw with Sigma rules)'; $l += "  $($A.Second.Summary)" }
    $l += ''; $l += 'BLIND SPOTS (what this scan could not see)'; foreach ($b in $A.Blind) { $l += "  - $b" }; if (-not $A.Blind.Count) { $l += '  - none identified' }
    $l += ''; $l += 'NEXT STEPS'; $i = 0; foreach ($n in $A.Next) { $i++; $l += "  $i. $n" }
    $l += ''; $l += 'Rule matches are leads for review, not proof of compromise, and no match is not proof of a clean machine. Full timeline and raw output are in the case folder.'
    ($l -join "`r`n") + "`r`n"
}

function New-QsHtml {
    param($A, $Meta)
    $col = switch ($A.Color) { 'green' { '#2e7d4f' } 'yellow' { '#9a7b17' } 'orange' { '#b4601a' } 'red' { '#a93232' } default { '#7a1f1f' } }
    $chips = ($A.Counts.GetEnumerator() | ForEach-Object { "<span class='chip $($_.Key)'>$($_.Key) $($_.Value)</span>" }) -join ' '
    $reasons = ($A.Reasons | ForEach-Object { "<li><b>+$($_.Points)</b> $(HtmlEnc $_.Text)</li>" }) -join ''
    $chain = ($A.Chain | ForEach-Object { $cls = if ($_.Serious) { 'hot' } elseif ($_.All) { 'warm' } else { '' }; "<div class='tac $cls'><div>$(HtmlEnc $_.Name)</div><b>$($_.All)</b></div>" }) -join ''
    $max = [math]::Max(1, (@($A.Hist | ForEach-Object { $_.Serious + $_.Other }) | Measure-Object -Maximum).Maximum)
    $bars = ($A.Hist | ForEach-Object { $h1 = [int](60 * $_.Serious / $max); $h2 = [int](60 * $_.Other / $max); "<div class='bar' title='$(HtmlEnc $_.Label): $($_.Serious) serious, $($_.Other) other'><div class='o' style='height:${h2}px'></div><div class='s' style='height:${h1}px'></div></div>" }) -join ''
    $top = ($A.Rules | Select-Object -First 20 | ForEach-Object { "<tr class='$($_.Sev)'><td>$($_.Sev)</td><td>$(HtmlEnc $_.Title)</td><td>$($_.Count)</td><td>$(HtmlEnc (Format-QsDate $_.First))</td><td>$(HtmlEnc (Format-QsDate $_.Last))</td><td class='mono'>$(HtmlEnc (($_.Sample + '').Substring(0, [Math]::Min(160, ($_.Sample + '').Length))))</td></tr>" }) -join "`n"
    $ent = { param($x) (($x | ForEach-Object { "$(HtmlEnc $_.Value) <small>($($_.Count))</small>" }) -join ', ') }
    $blind = ($A.Blind | ForEach-Object { "<li>$(HtmlEnc $_)</li>" }) -join ''; $next = ($A.Next | ForEach-Object { "<li>$(HtmlEnc $_)</li>" }) -join ''
    $sec = if ($A.Second) { "<h2>Second opinion (Chainsaw with Sigma rules)</h2><p>$(HtmlEnc $A.Second.Summary)</p>" } else { '' }
    $win = if ($A.Window) { "Incident window: <b>$(HtmlEnc (Format-QsDate $A.Window.From))</b> to <b>$(HtmlEnc (Format-QsDate $A.Window.To))</b> ($($A.Window.Hours) h)" } else { 'No serious findings, so no incident window.' }
    $cov = if ($A.Coverage) { "$($A.Coverage.FileCount) log files, $($A.Coverage.Events) events, $(HtmlEnc (Format-QsDate $A.Coverage.First)) to $(HtmlEnc (Format-QsDate $A.Coverage.Last))" } else { '' }
@"
<!doctype html><html><head><meta charset="utf-8"><title>Quick Scan - $(HtmlEnc $Meta.Case)</title><style>
body{background:#1e2126;color:#e6e8eb;font:14px Segoe UI,Arial,sans-serif;margin:0;padding:26px}h1{margin:0 0 4px}h2{color:#6aa8dc;border-bottom:1px solid #3e4652;padding-bottom:4px;margin-top:26px;font-size:16px}
.banner{background:$col;border-radius:6px;padding:16px 20px;margin:14px 0}.banner .v{font-size:26px;font-weight:600}.banner .s{opacity:.9}
.chip{display:inline-block;padding:2px 10px;border-radius:10px;margin-right:6px;background:#3e4652}.chip.critical{background:#7a1f1f}.chip.high{background:#8a4a1e}.chip.medium{background:#7a6a22}.chip.low{background:#274b78}
.tacs{display:flex;flex-wrap:wrap;gap:6px}.tac{background:#2b313a;border-radius:4px;padding:6px 10px;min-width:110px;font-size:12px;color:#9aa4b0}.tac b{display:block;font-size:18px;color:#6f7a86}.tac.warm b{color:#d9a441}.tac.hot{background:#4a2a2a}.tac.hot b{color:#ff8a8a}
.hist{display:flex;align-items:flex-end;gap:2px;height:66px;background:#252a31;padding:4px;border-radius:4px;overflow-x:auto}.bar{width:9px;display:flex;flex-direction:column;justify-content:flex-end}.bar .s{background:#e06c6c}.bar .o{background:#5a7aa8}
table{border-collapse:collapse;width:100%;font-size:12px}td,th{border:1px solid #3e4652;padding:4px 7px;text-align:left;vertical-align:top}th{background:#2b313a}tr.critical td:first-child{background:#7a1f1f}tr.high td:first-child{background:#8a4a1e}tr.medium td:first-child{background:#7a6a22}tr.low td:first-child{background:#274b78}
.mono{font-family:Consolas,monospace;word-break:break-all}small{color:#9aa4b0}.note{background:#252a31;border-left:3px solid #d9a441;padding:8px 12px;margin-top:20px}li{margin:3px 0}
</style></head><body>
<h1>Quick Scan</h1><div><small>Case $(HtmlEnc $Meta.Case) - scanned $(HtmlEnc $Meta.Scanned) UTC - source: $(HtmlEnc $Meta.Source) - $(HtmlEnc $Meta.Tools)</small></div>
<div class="banner"><div class="v">$(HtmlEnc $A.Verdict) <span class="s">- score $($A.Score)</span></div><div class="s">$(HtmlEnc $A.VerdictText)</div></div>
<p>$chips</p><p>$cov<br>$win</p>
<h2>Why this verdict</h2><ul>$reasons</ul>
<h2>Attack chain (MITRE ATT&amp;CK tactics seen)</h2><div class="tacs">$chain</div>
<h2>When (red = serious, blue = other findings)</h2><div class="hist">$bars</div>
<h2>Top findings</h2><table><tr><th>Level</th><th>What was detected</th><th>Hits</th><th>First</th><th>Last</th><th>Example</th></tr>$top</table>
<h2>Most involved</h2><p>Hosts: $(& $ent $A.Hosts)<br>Accounts: $(& $ent $A.Users)<br>Addresses: $(& $ent $A.Ips)</p>
$sec
<h2>Blind spots - what this scan could not see</h2><ul>$blind</ul>
<h2>Next steps</h2><ol>$next</ol>
<div class="note">Rule matches are leads for review, not proof of compromise. No match is not proof of a clean machine. Everything here was computed locally from the logs; nothing was sent anywhere.</div>
</body></html>
"@
}

function Invoke-QuickScan {
    # Source: @{ Kind = 'case'|'directory'|'file'|'live'; Path = ... }
    param([hashtable]$Source, [switch]$Fast, [switch]$SecondOpinion, [scriptblock]$OnProgress)
    $hi = Get-HayabusaInfo -Refresh
    $e = New-As4Entry 'quick_scan' 'Quick Scan' $global:CaseFolders.Rep 'event logs'
    $files = @(); $analysis = $null
    $step = { param($i, $n, $m) if ($OnProgress) { & $OnProgress $i $n $m } }
    try {
        if (-not $hi.Runnable) { $e.Status = 'SKIPPED'; $e.Notes += 'Hayabusa is not available (tools\Hayabusa).'; Start-As4Run 'quickscan' | Out-Null; $r = Complete-As4Entry $e @(); Stop-As4Run; return $r }
        $inputs = @(); $label = ''
        switch ($Source.Kind) {
            'case' { $dirs = @(Find-As4LogDirs $global:Case.Dir); if (-not $dirs.Count) { throw 'No .evtx files were found in this case. Export event logs first (Event Logs page) or choose another folder.' }; $inputs = @($dirs | ForEach-Object { @{ Kind = 'directory'; Path = $_.Dir; Names = $_.Names } }); $label = "all event logs in this case ($($dirs.Count) folder(s), $(($dirs | Measure-Object Files -Sum).Sum) files)" }
            'directory' { if (-not (Test-Path -LiteralPath $Source.Path -PathType Container)) { throw "Folder not found: $($Source.Path)" }; $nm = @(Get-ChildItem -LiteralPath $Source.Path -Recurse -File -Filter *.evtx -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }); if (-not $nm.Count) { throw "No .evtx files under $($Source.Path)" }; $inputs = @(@{ Kind = 'directory'; Path = $Source.Path; Names = $nm }); $label = $Source.Path }
            'file' { if (-not (Test-Path -LiteralPath $Source.Path -PathType Leaf)) { throw "File not found: $($Source.Path)" }; $inputs = @(@{ Kind = 'file'; Path = $Source.Path; Names = @($Source.Path) }); $label = $Source.Path }
            'live' { $inputs = @(@{ Kind = 'live'; Path = ''; Names = @(Get-ChildItem 'C:\Windows\System32\winevt\Logs' -Filter *.evtx -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }); $label = 'live event logs of this computer'; if (-not (Test-As4Admin)) { $e.Warnings += 'Not administrator: the Security log cannot be read, so logon activity is missing.' } }
            default { throw 'Choose where the logs are.' }
        }
        $e.Source = $label; $total = 2 * $inputs.Count + 3; $n = 0
        $rows = @(); $covRows = @(); $names = @(); $tlFiles = @(); $verbose = @()
        foreach ($in in $inputs) {
            if ($global:Cancel) { throw [OperationCanceledException]::new('cancelled') }
            $names += $in.Names; $spec = @{ Kind = $in.Kind; Path = $in.Path }
            $n++; & $step $n $total "Checking which logs there are ($($in.Path))"
            $cm = Invoke-Hayabusa -Command log-metrics -InSpec $spec -Options @{ utc = $true } -Id 'qs_coverage' -Title 'Quick Scan: log coverage'
            $cf = @($cm.Destination | Where-Object { $_ -like '*log-metrics.csv' } | Select-Object -First 1); if ($cf.Count) { $covRows += @(Import-Csv -LiteralPath (Join-Path $global:Case.Dir $cf[0]) -Encoding UTF8) }
            if ($global:Cancel) { throw [OperationCanceledException]::new('cancelled') }
            $n++; & $step $n $total "Running the detection rules ($($in.Path))"
            $o = @{ profile = 'verbose'; utc = $true; 'html-report' = $true }; if ($Fast) { $o['min-level'] = 'medium' }
            $tm = Invoke-Hayabusa -Command dfir-timeline -InSpec $spec -Options $o -Id 'qs_timeline' -Title 'Quick Scan: detection timeline'
            if ($tm.Status -notin 'OK', 'SKIPPED') { $e.Warnings += "Timeline for $($in.Path): $($tm.Status) $(@($tm.Notes) -join ' ')" }
            $tf = @($tm.Destination | Where-Object { $_ -like '*timeline.csv' } | Select-Object -First 1); if ($tf.Count) { $p = Join-Path $global:Case.Dir $tf[0]; if ((Get-Item -LiteralPath $p).Length -gt 0) { $rows += @(Import-Csv -LiteralPath $p -Encoding UTF8) }; $tlFiles += $p }
        }
        $second = $null
        if ($SecondOpinion) {
            $n++; & $step $n $total 'Second opinion with Chainsaw'
            $ci = Get-ChainsawInfo
            if ($ci.Runnable -and $Source.Kind -ne 'live') {
                $ins = @($inputs | ForEach-Object { $_.Path }); $O = @{ Input = $ins; Format = 'json'; Sigma = (Resolve-ChainsawRel $ci.Dir 'sigma/rules'); Rules = (Resolve-ChainsawRel $ci.Dir 'rules'); Mapping = (Resolve-ChainsawRel $ci.Dir 'mappings/sigma-event-logs-all.yml'); Level = @('high', 'critical'); SkipErrors = $true }
                $cr = Invoke-Chainsaw -Sub hunt -O $O; $jf = @($cr.Destination | Where-Object { $_ -like '*results.json' } | Select-Object -First 1)
                $cnt = 0; $names2 = @(); if ($jf.Count) { try { $d = @(Import-ChainsawResults (Join-Path $global:Case.Dir $jf[0])); $cnt = $d.Count; $names2 = @($d | Group-Object Detection | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Count))" }) } catch {} }
                $second = [pscustomobject]@{ Count = $cnt; Status = $cr.Status; Summary = $(if ($cr.Status -eq 'OK') { "Chainsaw found $cnt high or critical Sigma detections." + $(if ($names2.Count) { " Top: $($names2 -join '; ')." } else { '' }) } else { "Chainsaw did not complete ($($cr.Status))." }) }
            } else { $second = [pscustomobject]@{ Count = 0; Status = 'SKIPPED'; Summary = 'Chainsaw is not available for this input.' } }
        }
        $n++; & $step $n $total 'Working out the verdict'
        $cov = Get-QsCoverage -Rows $covRows -Names $names
        $analysis = Get-QsAnalysis -Rows $rows -Coverage $cov -Second $second
        Start-As4Run 'quickscan-summary' | Out-Null
        $meta = @{ Case = $global:Case.Id; Scanned = (Get-UtcIso); Source = $label; Tools = "$($hi.Version)$(if ($Fast) { ' (fast mode: medium and above)' })" }
        $rep = Get-CaseFolder 'Rep'
        $hf = Get-UniquePath $rep 'quickscan_summary' 'html'; Write-As4File $hf (New-QsHtml $analysis $meta); $files += $hf
        $tf2 = Get-UniquePath $rep 'quickscan_summary' 'txt'; Write-As4File $tf2 (New-QsText $analysis $meta); $files += $tf2
        if ($rows.Count -and $inputs.Count -gt 1) { $mf = Get-UniquePath $rep 'quickscan_timeline_merged' 'csv'; $rows | Export-Csv -LiteralPath $mf -NoTypeInformation -Encoding UTF8; $files += $mf }
        $e.Command = 'AS4 Quick Scan'; $e.Arguments = "Hayabusa dfir-timeline profile verbose$(if ($Fast) { ', min-level medium' })$(if ($SecondOpinion) { ' + Chainsaw hunt (Sigma, high/critical)' })"; $e.ToolVersion = $hi.Version; $e.Status = 'OK'
        $e.Notes += "Verdict: $($analysis.Verdict) (score $($analysis.Score)); $($analysis.Total) rule matches; $(@($analysis.Blind).Count) blind spot(s). Rule matches are leads, not proof."
        $analysis | Add-Member -NotePropertyName HtmlPath -NotePropertyValue $hf -Force; $analysis | Add-Member -NotePropertyName TextPath -NotePropertyValue $tf2 -Force; $analysis | Add-Member -NotePropertyName TimelineFiles -NotePropertyValue $tlFiles -Force
        $analysis | Add-Member -NotePropertyName Source -NotePropertyValue $label -Force
    } catch [OperationCanceledException] { $e.Status = 'CANCELLED'; $e.Notes += 'Cancelled.'; Start-As4Run 'quickscan-summary' | Out-Null }
    catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message; Start-As4Run 'quickscan-summary' | Out-Null }
    $res = Complete-As4Entry $e $files 'derived'; Stop-As4Run
    $res | Add-Member -NotePropertyName Analysis -NotePropertyValue $analysis -Force -PassThru
}
