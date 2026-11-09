# AS4 IR Tool - Live Hunt runner and report. ASCII only. Read-only on the machine; writes only inside the case folder.

function Format-LhTime { param($s) if (-not $s) { return '' }; try { ([datetime]$s).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' } catch { [string]$s } }

function Invoke-LiveHunt {
    param([int]$EventDays = 14, [switch]$SkipFiles, [switch]$SkipEvents, [scriptblock]$OnProgress)
    if (-not $global:Case) { throw 'No active case.' }
    $gentle = Test-LhGentle; $gentleFiles = $false; if ($gentle -and -not $SkipFiles) { $SkipFiles = [switch]$true; $gentleFiles = $true }
    $e = New-As4Entry 'livehunt' 'Live Hunt' $global:CaseFolders.Live
    Start-As4Run 'livehunt' | Out-Null; $started = Get-UtcNow
    $res = [ordered]@{ Status = 'FAILED'; Notes = @(); Findings = @(); Verdict = $null; Inventory = $null; Files = @{} }
    $raw = @(); $derived = @()
    try {
        $global:LhS = 0; $stepsTotal = 6 + $(if ($SkipFiles) { 0 } else { 1 }) + $(if ($SkipEvents) { 0 } else { 1 })
        $tick = { param($m) $global:LhS++; if ($OnProgress) { & $OnProgress $global:LhS $stepsTotal $m }; if ($global:UiPump) { & $global:UiPump } }
        $outer = $OnProgress
        $inv = Get-LhInventory -OnProgress { param($i, $n, $m) if ($outer) { & $outer $i $n $m }; if ($global:UiPump) { & $global:UiPump } }
        $all = New-Object Collections.ArrayList
        $sets = @(@('Checking processes', { Test-LhProcesses $inv }), @('Checking network connections', { Test-LhNetwork $inv }), @('Checking services and drivers', { Test-LhServices $inv }), @('Checking persistence', { Test-LhPersistence $inv }), @('Checking accounts, defences and known tools', { @(Test-LhAccounts $inv) + @(Test-LhPosture $inv) + @(Test-LhTools $inv) + @(Test-LhPipes $inv) }))
        if (-not $SkipEvents) { $sets += , @(('Reading event logs (last ' + $EventDays + ' days)'), { Test-LhEvents $inv $EventDays }) }
        if (-not $SkipFiles) { $sets += , @('Looking for recently dropped files', { Test-LhFiles }) }
        $sets += , @('Preparing the report', { @() })
        foreach ($s in $sets) {
            if ($global:Cancel) { $e.Status = 'CANCELLED'; throw [OperationCanceledException]::new('cancelled') }
            & $tick $s[0]
            try { foreach ($x in @(& $s[1])) { if ($x) { [void]$all.Add($x) } } } catch { $inv.Errors.Add("$($s[0]): $($_.Exception.Message)") | Out-Null; Write-As4Log WARN "Live Hunt step failed: $($s[0]): $($_.Exception.Message)" }
        }
        $selfN = @($all | Where-Object { Test-As4SelfText "$($_.Title) $($_.Detail)" }).Count; if ($selfN) { $all = @($all | Where-Object { -not (Test-As4SelfText "$($_.Title) $($_.Detail)") }) }
        $sevOrder = @{ high = 0; medium = 1; low = 2; info = 3 }
        $findings = @($all | Sort-Object @{ e = { $sevOrder[$_.Sev] } }, Area, Title)
        $v = Get-LhVerdict $findings; $next = Get-LhNextSteps $findings $v; $blind = @(Get-LhBlindSpots $inv); if ($gentleFiles) { $blind = @('This looks like a server or a busy machine, so AS4 ran in gentle mode: pauses between checks and no scan of recently dropped files.') + $blind }; if ($selfN) { $blind = @("$selfN item(s) were caused by AS4 itself (its own commands, scripts, rule files and exports) and were left out.") + $blind }
        $dir = Get-CaseFolder 'Live'
        # raw: what the machine looked like. derived: what we concluded.
        $invFile = Get-UniquePath $dir 'hunt_inventory' 'json'; Write-As4File $invFile ($inv | ConvertTo-Json -Depth 6); $raw += $invFile
        $csv = Get-UniquePath $dir 'hunt_findings' 'csv'; Write-As4File $csv (($findings | Select-Object Sev, Area, Title, Detail, Mitre, Why, Next, ProcessId | ConvertTo-Csv -NoTypeInformation) -join "`r`n"); $derived += $csv
        $fj = Get-UniquePath $dir 'hunt_findings' 'json'; Write-As4File $fj (@{ Verdict = $v; Findings = $findings; Next = $next; BlindSpots = $blind } | ConvertTo-Json -Depth 6); $derived += $fj
        $html = Get-UniquePath $dir 'LiveHunt' 'html'; Write-As4File $html (New-LhHtml $inv $findings $v $next $blind $started); $derived += $html
        $txt = Get-UniquePath $dir 'LiveHunt' 'txt'; Write-As4File $txt (New-LhText $inv $findings $v $next $blind); $derived += $txt
        $res.Findings = $findings; $res.Verdict = $v; $res.Inventory = $inv; $res.Next = $next; $res.Blind = $blind
        $res.Files = @{ Html = $html; Text = $txt; Csv = $csv; Json = $fj; Inventory = $invFile }
        $cnt = @{ high = 0; medium = 0; low = 0; info = 0 }; foreach ($x in $findings) { $cnt[$x.Sev]++ }; $res.Counts = $cnt
        $e.Status = 'OK'; $e.Notes += "Verdict: $($v.Verdict) (score $($v.Score)); high $($cnt.high), medium $($cnt.medium), low $($cnt.low), info $($cnt.info)."
        $e.Notes += 'Derived files: ' + ((($derived | ForEach-Object { Get-RelPath $_ }) -join '; '))
        $e.Command = 'powershell (in-process, read-only)'; $e.ToolVersion = "AS4 $($global:AS4Version)"
    } catch [OperationCanceledException] { $e.Status = 'CANCELLED' }
    catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message; Write-As4Log ERROR "Live Hunt: $($_.Exception.Message)" }
    $out = Complete-As4Entry $e $raw 'raw'
    if ($derived.Count) { Register-As4Files $derived 'derived' | Out-Null }
    Stop-As4Run
    $res.Status = $out.Status; $res.Notes = @($out.Notes); $res.Entry = $out
    [pscustomobject]$res
}

# ---------- text summary ----------
function New-LhText {
    param($Inv, $Findings, $V, $Next, $Blind)
    $h = Get-As4Host; $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('AS4 IR Tool - Live Hunt'); [void]$sb.AppendLine("Computer: $($h.Computer)   User: $($h.User)   Administrator: $($Inv.Admin)"); [void]$sb.AppendLine("Taken: $($Inv.Taken)"); [void]$sb.AppendLine('')
    [void]$sb.AppendLine("VERDICT: $($V.Verdict)   (score $($V.Score))"); [void]$sb.AppendLine($V.Text); [void]$sb.AppendLine('')
    [void]$sb.AppendLine('WHY'); foreach ($r in $V.Reasons | Select-Object -First 12) { [void]$sb.AppendLine("  +$($r.Points)  $($r.Text)") }
    foreach ($sev in 'high', 'medium', 'low', 'info') { $g = @($Findings | Where-Object Sev -eq $sev); if (-not $g.Count) { continue }
        [void]$sb.AppendLine(''); [void]$sb.AppendLine(($sev.ToUpper() + " ($($g.Count))")); foreach ($x in $g) { [void]$sb.AppendLine("  [$($x.Area)] $($x.Title)"); [void]$sb.AppendLine("      $($x.Detail)"); if ($x.Mitre) { [void]$sb.AppendLine("      MITRE $($x.Mitre)") } } }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('NEXT STEPS'); $i = 0; foreach ($n in $Next) { $i++; [void]$sb.AppendLine("  $i. $n") }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('WHAT THIS CHECK COULD NOT SEE'); foreach ($b in $Blind) { [void]$sb.AppendLine("  - $b") }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('Every item is a lead for a person to confirm, not proof. Nothing on this machine was changed.')
    $sb.ToString()
}

# ---------- process tree for the report ----------
function ConvertTo-LhTreeHtml {
    param($Inv, $Findings)
    $by = @{}; $kids = @{}; foreach ($p in $Inv.Processes) { $by[[int]$p.ProcessId] = $p }
    $flag = @{}; foreach ($x in $Findings) { if ($x.ProcessId) { $k = [int]$x.ProcessId; if (-not $flag.ContainsKey($k) -or $x.Sev -eq 'high') { $flag[$k] = $x.Sev } } }
    $roots = New-Object Collections.ArrayList
    foreach ($p in $Inv.Processes) { $pp = [int]$p.ParentProcessId; if ($by.ContainsKey($pp) -and $pp -ne [int]$p.ProcessId -and -not ([string]$by[$pp].Created -gt [string]$p.Created)) { if (-not $kids.ContainsKey($pp)) { $kids[$pp] = New-Object Collections.ArrayList }; [void]$kids[$pp].Add($p) } else { [void]$roots.Add($p) } }
    $sb = New-Object Text.StringBuilder; $count = 0
    $emit = $null
    $emit = { param($p, $depth)
        if ($depth -gt 14 -or $script:LhTreeCount -gt 1500) { return }
        $script:LhTreeCount++
        $cls = ''; if ($flag.ContainsKey([int]$p.ProcessId)) { $cls = " class='f-$($flag[[int]$p.ProcessId])'" }
        $cmd = [string]$p.CommandLine; if ($cmd.Length -gt 160) { $cmd = $cmd.Substring(0, 160) + '...' }
        $tip = HtmlEnc ([string]$p.ExecutablePath); $nm = HtmlEnc ([string]$p.Name)
        [void]$sb.Append("<li$cls><span class='pn' title='$tip'>$nm</span> <span class='pid'>PID $($p.ProcessId)</span>")
        if ($flag.ContainsKey([int]$p.ProcessId)) { [void]$sb.Append(" <span class='tag $($flag[[int]$p.ProcessId])'>$($flag[[int]$p.ProcessId])</span>") }
        if ($cmd) { [void]$sb.Append(" <span class='cmd'>" + (HtmlEnc $cmd) + '</span>') }
        $c = $kids[[int]$p.ProcessId]
        if ($c -and $c.Count) { [void]$sb.Append('<ul>'); foreach ($k in ($c | Sort-Object Created)) { & $emit $k ($depth + 1) }; [void]$sb.Append('</ul>') }
        [void]$sb.Append('</li>') }
    $script:LhTreeCount = 0
    [void]$sb.Append("<ul class='tree'>"); foreach ($r in ($roots | Sort-Object Created)) { & $emit $r 0 }; [void]$sb.Append('</ul>')
    $sb.ToString()
}

# ---------- HTML report (one file, no external links) ----------
function New-LhHtml {
    param($Inv, $Findings, $V, $Next, $Blind, $Started)
    $h = Get-As4Host; $e = { param($s) HtmlEnc $s }
    $col = switch ($V.Color) { 'green' { '#2e7d4f' } 'yellow' { '#9a7b17' } 'orange' { '#b4601a' } 'red' { '#a93232' } default { '#7a1f1f' } }
    $cnt = @{ high = 0; medium = 0; low = 0; info = 0 }; foreach ($x in $Findings) { $cnt[$x.Sev]++ }
    $fh = New-Object Text.StringBuilder
    foreach ($sev in 'high', 'medium', 'low', 'info') { $g = @($Findings | Where-Object Sev -eq $sev); if (-not $g.Count) { continue }
        [void]$fh.Append("<h3><span class='tag $sev'>$sev</span> $($g.Count) item(s)</h3>")
        foreach ($x in $g) { [void]$fh.Append("<details class='fnd $sev'><summary><b>" + (& $e $x.Title) + "</b> <span class='area'>" + (& $e $x.Area) + "</span><div class='det'>" + (& $e $x.Detail) + "</div></summary><div class='body'>")
            if ($x.Why) { [void]$fh.Append('<p><b>Why it matters.</b> ' + (& $e $x.Why) + '</p>') }; if ($x.Next) { [void]$fh.Append('<p><b>What to do next.</b> ' + (& $e $x.Next) + '</p>') }; if ($x.Mitre) { [void]$fh.Append("<p class='dim'>MITRE ATT&amp;CK " + (& $e $x.Mitre) + '</p>') }; [void]$fh.Append('</div></details>') } }
    if (-not $Findings.Count) { [void]$fh.Append("<p class='dim'>No findings.</p>") }
    $by = @{}; foreach ($p in $Inv.Processes) { $by[[int]$p.ProcessId] = $p }
    $ext = @($Inv.Connections | Where-Object { $_.Proto -eq 'TCP' -and $_.State -in 'Established', 'SynSent' -and -not (Test-LhPrivateIp $_.RemoteAddress) } | Sort-Object RemoteAddress)
    $erows = ($ext | Select-Object -First 80 | ForEach-Object { $p = $by[[int]$_.ProcessId]; "<tr><td>" + (& $e $(if ($p) { $p.Name } else { '?' })) + "</td><td>$($_.ProcessId)</td><td class='mono'>" + (& $e "$($_.RemoteAddress):$($_.RemotePort)") + "</td><td>" + (& $e $_.State) + "</td><td class='mono'>" + (& $e $(if ($p) { $p.ExecutablePath } else { '' })) + '</td></tr>' }) -join ''
    $lst = @($Inv.Connections | Where-Object { $_.State -eq 'Listen' -and $_.LocalAddress -notin '127.0.0.1', '::1' } | Sort-Object LocalPort -Unique)
    $lrows = ($lst | Select-Object -First 80 | ForEach-Object { $p = $by[[int]$_.ProcessId]; "<tr><td>$($_.Proto)</td><td>$($_.LocalPort)</td><td>" + (& $e $(if ($p) { $p.Name } else { '?' })) + "</td><td>$($_.ProcessId)</td></tr>" }) -join ''
    $ev = ''; if ($Inv.LogChannels) { $ev = ($Inv.LogChannels | ForEach-Object { $st = 'dim'; $en = 'no'; if ($_.Exists) { $en = $(if ($_.Enabled) { 'yes' } else { 'OFF' }) }; $rg = ''; if ($_.Oldest) { $rg = (Format-LhTime $_.Oldest) + ' to ' + (Format-LhTime $_.Newest) }; $nt = $_.Note; if ($_.NeedsAdmin -and -not $Inv.Admin) { $nt = 'needs administrator' }
        "<tr><td>" + (& $e $_.Channel) + "</td><td>$en</td><td>$($_.Records)</td><td>$rg</td><td class='dim'>" + (& $e $_.Use) + ' ' + (& $e $nt) + '</td></tr>' }) -join '' }
    $adm = (@($Inv.Admins | ForEach-Object { & $e $_.Name }) -join ', ')
    $tree = ConvertTo-LhTreeHtml $Inv $Findings
    $why = ($V.Reasons | Select-Object -First 12 | ForEach-Object { "<li><b>+$($_.Points)</b> " + (& $e $_.Text) + '</li>' }) -join ''
    $nx = ($Next | ForEach-Object { '<li>' + (& $e $_) + '</li>' }) -join ''; $bl = ($Blind | ForEach-Object { '<li>' + (& $e $_) + '</li>' }) -join ''
@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Live Hunt - $(& $e $h.Computer)</title><style>
:root{--bg:#0d1211;--panel:#151c1a;--line:#26342f;--text:#d9dfe6;--dim:#8d99a6;--accent:#3ddc84}
body{background:var(--bg);color:var(--text);font:14px/1.5 Segoe UI,Arial,sans-serif;margin:0;padding:0 0 40px}
.wrap{max-width:1100px;margin:0 auto;padding:0 20px}h1{margin:22px 0 2px;font-size:22px}h2{border-bottom:1px solid var(--line);padding-bottom:5px;margin:30px 0 10px;color:var(--accent);font-size:16px}h3{margin:18px 0 6px;font-size:14px}
.ban{background:$col;color:#fff;padding:18px 22px;border-radius:6px;margin:14px 0}.ban .v{font-size:24px;font-weight:700}.ban .s{opacity:.9;margin-top:4px}
.dim{color:var(--dim)}.mono{font-family:Consolas,monospace;font-size:12px;word-break:break-all}
table{border-collapse:collapse;width:100%;margin:6px 0}td,th{border:1px solid var(--line);padding:4px 8px;text-align:left;vertical-align:top;font-size:12.5px}th{background:var(--panel)}
.tag{display:inline-block;padding:1px 8px;border-radius:9px;font-size:11px;font-weight:700;text-transform:uppercase;background:#2c3541}.tag.high{background:#8c2f2f;color:#fff}.tag.medium{background:#8a6a1b;color:#fff}.tag.low{background:#2d5a85;color:#fff}.tag.info{background:#3a4552}
details.fnd{background:var(--panel);border-left:4px solid var(--line);margin:6px 0;border-radius:3px}details.fnd.high{border-left-color:#c24a4a}details.fnd.medium{border-left-color:#c79a2c}details.fnd.low{border-left-color:#4a86c2}
details.fnd summary{cursor:pointer;padding:8px 12px;list-style:none}.area{color:var(--dim);font-size:12px;margin-left:8px}.det{color:var(--dim);font-size:12.5px;margin-top:2px;word-break:break-all}.body{padding:2px 14px 10px}
.pills span{display:inline-block;margin-right:8px}.grid{display:flex;gap:18px;flex-wrap:wrap}.grid>div{flex:1;min-width:300px}
ul.tree,ul.tree ul{list-style:none;padding-left:18px;margin:2px 0;border-left:1px dotted var(--line)}ul.tree{border:0;padding-left:0}ul.tree li{margin:1px 0;font-size:12.5px}.pn{font-weight:600}.pid{color:var(--dim);font-size:11px}.cmd{color:var(--dim);font-family:Consolas,monospace;font-size:11px}li.f-high>.pn{color:#ff8a8a}li.f-medium>.pn{color:#f0c060}li.f-low>.pn{color:#8cbcf0}
.note{background:var(--panel);border-left:3px solid #c79a2c;padding:8px 12px;margin:10px 0}
</style></head><body><div class="wrap">
<h1>$(Get-As4BirdSvg 30) Live Hunt</h1><div class="dim">$(& $e $h.Computer) &middot; $(& $e $h.OS) &middot; user $(& $e $h.User) &middot; administrator: $($Inv.Admin) &middot; taken $(& $e (Format-LhTime $Inv.Taken)) &middot; AS4 IR Tool $($global:AS4Version)</div>
<div class="ban"><div class="v">$(& $e $V.Verdict) &nbsp;<span style="font-weight:400;font-size:16px">score $($V.Score)</span></div><div class="s">$(& $e $V.Text)</div></div>
<div class="pills"><span class="tag high">high $($cnt.high)</span><span class="tag medium">medium $($cnt.medium)</span><span class="tag low">low $($cnt.low)</span><span class="tag info">info $($cnt.info)</span></div>
<h2>Why this verdict</h2><ul>$why</ul>
<h2>Findings</h2>$($fh.ToString())
<h2>Next steps</h2><ol>$nx</ol>
<h2>Process tree</h2><div class="dim">Coloured names have findings. Hover a name for the full path. AS4's own processes are not flagged.</div>$tree
<div class="grid"><div><h2>Connections to the internet</h2><table><tr><th>Program</th><th>PID</th><th>Remote</th><th>State</th><th>Path</th></tr>$erows</table></div>
<div><h2>Listening ports (not local only)</h2><table><tr><th>Proto</th><th>Port</th><th>Program</th><th>PID</th></tr>$lrows</table></div></div>
<h2>What evidence exists on this machine</h2><div class="dim">Use this to decide what to collect and how far back the logs go.</div><table><tr><th>Log</th><th>On</th><th>Records</th><th>Covers</th><th>Notes</th></tr>$ev</table>
<h2>Local administrators</h2><p>$adm</p>
<h2>What this check could not see</h2><ul>$bl</ul>
<div class="note"><b>How to read this.</b> AS4 only looked; it did not stop, change, delete or send anything. Every item is a lead for a person to confirm. Nothing here proves a machine is clean or compromised.</div>
</div></body></html>
"@
}
