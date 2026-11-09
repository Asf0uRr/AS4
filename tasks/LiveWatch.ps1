# AS4 IR Tool - Live Watch (what starts and connects while you watch) and Snapshot / Compare (what changed). ASCII only.
# Polling only: AS4 asks Windows what exists every few seconds. No event subscriptions, no drivers, nothing installed, nothing changed.

function Invoke-LiveWatch {
    param([int]$Seconds = 120, [int]$IntervalSec = 3, [scriptblock]$OnProgress)
    if (-not $global:Case) { throw 'No active case.' }
    $Seconds = [Math]::Max(10, [Math]::Min(3600, $Seconds)); $IntervalSec = [Math]::Max(2, [Math]::Min(30, $IntervalSec)); if ((Test-LhGentle) -and $IntervalSec -lt 5) { $IntervalSec = 5 }
    $e = New-As4Entry 'livewatch' 'Live Watch' $global:CaseFolders.Live
    Start-As4Run 'livewatch' | Out-Null; $started = Get-UtcNow
    $events = New-Object Collections.ArrayList; $findings = New-Object Collections.ArrayList
    $res = [ordered]@{ Status = 'FAILED'; Notes = @(); Events = @(); Findings = @(); Files = @{}; Seconds = $Seconds }
    $files = @(); $derived = @()
    try {
        $self = $PID
        $seenProc = @{}; $flows = @{}; $listen = @{}; $dnsSeen = @{}; $liveNow = @{}; $reported = @{}
        $addEv = { param($type, $what, $detail, $pid0) [void]$events.Add([pscustomobject]@{ TimeUtc = (Get-UtcIso); Type = $type; Subject = $what; Detail = $detail; ProcessId = $pid0 }) }
        $poll = {
            param($first)
            $procs = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine, CreationDate -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ ProcessId = [int]$_.ProcessId; ParentProcessId = [int]$_.ParentProcessId; Name = [string]$_.Name; ExecutablePath = [string]$_.ExecutablePath; CommandLine = [string]$_.CommandLine; Created = $(if ($_.CreationDate) { $_.CreationDate.ToUniversalTime().ToString('o') } else { '' }) } })
            $by = @{}; foreach ($p in $procs) { $by[[int]$p.ProcessId] = $p }
            $skip = Get-LhDescendants $by
            $now = @{}
            foreach ($p in $procs) { $k = "$($p.ProcessId)|$($p.Created)"; $now[$k] = $p
                if (-not $seenProc.ContainsKey($k)) { $seenProc[$k] = $p
                    if (-not $first -and -not $skip.Contains([int]$p.ProcessId)) {
                        $pn = ''; if ($by.ContainsKey([int]$p.ParentProcessId)) { $pn = $by[[int]$p.ParentProcessId].Name }
                        $cl = $p.CommandLine; if ($cl.Length -gt 300) { $cl = $cl.Substring(0, 300) + '...' }
                        $reported[$k] = 1
                        & $addEv 'process started' $p.Name "parent $pn ($($p.ParentProcessId)) | $($p.ExecutablePath) | $cl" $p.ProcessId
                        foreach ($x in @(Test-LhProcess $p $by $skip)) { $x | Add-Member -NotePropertyName SeenUtc -NotePropertyValue (Get-UtcIso) -Force; [void]$findings.Add($x) } } } }
            foreach ($k in @($liveNow.Keys)) { if (-not $now.ContainsKey($k)) { $p = $liveNow[$k]; if ($reported.ContainsKey($k)) { & $addEv 'process ended' $p.Name "PID $($p.ProcessId)" $p.ProcessId } } }
            $liveNow.Clear(); foreach ($k in $now.Keys) { $liveNow[$k] = $now[$k] }
            try {
                $cur = @{}
                foreach ($c in (Get-NetTCPConnection -ErrorAction Stop | Where-Object { $_.State -in 'Established', 'SynSent', 'Listen' })) {
                    $pr = $by[[int]$c.OwningProcess]; $pname = ''; if ($pr) { $pname = $pr.Name }
                    if ($skip.Contains([int]$c.OwningProcess)) { continue }
                    if ($c.State -eq 'Listen') { $lk = "$($c.LocalAddress):$($c.LocalPort)|$($c.OwningProcess)"; if (-not $listen.ContainsKey($lk)) { $listen[$lk] = 1; if (-not $first -and $c.LocalAddress -notin '127.0.0.1', '::1') { & $addEv 'new listener' $pname "port $($c.LocalPort) ($($c.LocalAddress)) PID $($c.OwningProcess)" $c.OwningProcess } }; continue }
                    if (Test-LhPrivateIp $c.RemoteAddress) { continue }
                    $fk = "$($c.OwningProcess)|$($c.RemoteAddress)|$($c.RemotePort)"; $cur[$fk] = 1
                    if (-not $flows.ContainsKey($fk)) { $flows[$fk] = [pscustomobject]@{ Name = $pname; Path = $(if ($pr) { $pr.ExecutablePath } else { '' }); Pid0 = $c.OwningProcess; Remote = "$($c.RemoteAddress):$($c.RemotePort)"; Starts = New-Object Collections.ArrayList; Present = $false; SynSent = 0 } }
                    $fl = $flows[$fk]; if ($c.State -eq 'SynSent') { $fl.SynSent++ }
                    if (-not $fl.Present) { [void]$fl.Starts.Add((Get-Date)); if (-not $first) { & $addEv 'new connection' $pname "$($c.State) to $($c.RemoteAddress):$($c.RemotePort) PID $($c.OwningProcess)" $c.OwningProcess } }
                }
                foreach ($k in $flows.Keys) { $flows[$k].Present = $cur.ContainsKey($k) }
            } catch {}
            try { foreach ($d in (Get-DnsClientCache -ErrorAction Stop)) { $dn = [string]$d.Entry; if ($dn -and -not $dnsSeen.ContainsKey($dn)) { $dnsSeen[$dn] = 1; if (-not $first) { & $addEv 'name looked up' $dn "type $($d.Type) -> $($d.Data)" '' } } } } catch {}
        }
        & $poll $true
        $end = (Get-Date).AddSeconds($Seconds); $n = 0
        while ((Get-Date) -lt $end -and -not $global:Cancel) {
            $until = (Get-Date).AddSeconds($IntervalSec)
            while ((Get-Date) -lt $until -and -not $global:Cancel) { Start-Sleep -Milliseconds 150; if ($global:UiPump) { & $global:UiPump } }
            & $poll $false; $n++
            if ($OnProgress) { & $OnProgress ([int]($Seconds - ($end - (Get-Date)).TotalSeconds)) $Seconds "$($events.Count) event(s), $($findings.Count) lead(s)" }
        }
        # repeated reconnects to the same address look like a beacon
        foreach ($fl in $flows.Values) {
            $st = @($fl.Starts); if ($st.Count -ge 3) {
                $iv = @(); for ($i = 1; $i -lt $st.Count; $i++) { $iv += ($st[$i] - $st[$i - 1]).TotalSeconds }
                $avg = ($iv | Measure-Object -Average).Average; $dev = 0; foreach ($x in $iv) { $dev += [Math]::Pow($x - $avg, 2) }; $sd = [Math]::Sqrt($dev / $iv.Count)
                if ($avg -gt 0 -and ($sd / $avg) -lt 0.35) { [void]$findings.Add((New-LhFinding 'medium' 'Network' 'Regular reconnects to the same internet address' "$($fl.Name) (PID $($fl.Pid0)) connected to $($fl.Remote) $($st.Count) times, about every $([int]$avg) s" 'T1071' 'A steady rhythm of short connections is how many remote-control programs check in. Update checkers and chat apps do it too.' 'Look at the program and the address; compare with a normal day if you can.' $fl.Pid0)) } }
            if ($fl.SynSent -ge 3) { [void]$findings.Add((New-LhFinding 'medium' 'Network' 'Repeated failed attempts to reach the same internet address' "$($fl.Name) (PID $($fl.Pid0)) -> $($fl.Remote), $($fl.SynSent) tries with no answer" 'T1071' 'A program that keeps retrying an address that does not answer may be waiting for its controller.' 'Note the address and the program.' $fl.Pid0)) } }
        $findings = @($findings | Where-Object { -not (Test-As4SelfText "$($_.Title) $($_.Detail)") })
        $sevOrder = @{ high = 0; medium = 1; low = 2; info = 3 }
        $fnd = @($findings | Sort-Object @{ e = { $sevOrder[$_.Sev] } }, Title)
        $v = Get-LhVerdict $fnd
        $dir = Get-CaseFolder 'Live'
        $csv = Get-UniquePath $dir 'watch_events' 'csv'; Write-As4File $csv (($events | ConvertTo-Csv -NoTypeInformation) -join "`r`n"); $files += $csv
        $js = Get-UniquePath $dir 'watch_events' 'json'; Write-As4File $js (@{ Seconds = $Seconds; IntervalSec = $IntervalSec; Events = $events; Findings = $fnd } | ConvertTo-Json -Depth 5); $files += $js
        $tx = Get-UniquePath $dir 'LiveWatch' 'txt'; Write-As4File $tx (New-LwText $events $fnd $v $Seconds $IntervalSec $started); $derived += $tx
        $ht = Get-UniquePath $dir 'LiveWatch' 'html'; Write-As4File $ht (New-LwHtml $events $fnd $v $Seconds $IntervalSec); $derived += $ht
        $e.Status = $(if ($global:Cancel) { 'CANCELLED' } else { 'OK' })
        $e.Notes += "Watched $Seconds s, polling every $IntervalSec s: $($events.Count) event(s), $($fnd.Count) lead(s). Programs that start and end between two polls are not seen."
        $e.Command = 'powershell (in-process, polling, read-only)'; $e.ToolVersion = "AS4 $($global:AS4Version)"
        $res.Events = @($events); $res.Findings = $fnd; $res.Verdict = $v; $res.Files = @{ Html = $ht; Text = $tx; Csv = $csv; Json = $js }
    } catch [OperationCanceledException] { $e.Status = 'CANCELLED' }
    catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message; Write-As4Log ERROR "Live Watch: $($_.Exception.Message)" }
    $out = Complete-As4Entry $e $files 'raw'
    if ($derived.Count) { Register-As4Files $derived 'derived' | Out-Null }
    Stop-As4Run
    $res.Status = $out.Status; $res.Notes = @($out.Notes)
    [pscustomobject]$res
}

function New-LwText {
    param($Events, $Findings, $V, $Seconds, $Interval, $Started)
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('AS4 IR Tool - Live Watch'); [void]$sb.AppendLine("Watched $Seconds seconds, checking every $Interval seconds, starting $(Get-UtcIso $Started)"); [void]$sb.AppendLine("Verdict: $($V.Verdict) (score $($V.Score))"); [void]$sb.AppendLine('')
    foreach ($x in $Findings) { [void]$sb.AppendLine("[$($x.Sev)] $($x.Title)"); [void]$sb.AppendLine("    $($x.Detail)") }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('EVENTS (UTC)'); foreach ($ev in $Events) { [void]$sb.AppendLine(("{0}  {1,-16} {2}  {3}" -f $ev.TimeUtc.Substring(11, 8), $ev.Type, $ev.Subject, $ev.Detail)) }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('Polling cannot see programs that start and end between two checks. Every lead needs a person to confirm it.')
    $sb.ToString()
}

function New-LwHtml {
    param($Events, $Findings, $V, $Seconds, $Interval)
    $e = { param($s) HtmlEnc $s }; $h = Get-As4Host
    $fh = ($Findings | ForEach-Object { "<tr><td><span class='tag $($_.Sev)'>$($_.Sev)</span></td><td><b>" + (& $e $_.Title) + "</b><div class='dim'>" + (& $e $_.Detail) + '</div></td></tr>' }) -join ''
    $rows = ($Events | ForEach-Object { "<tr><td class='mono'>" + (& $e $_.TimeUtc.Substring(11, 8)) + '</td><td>' + (& $e $_.Type) + '</td><td>' + (& $e $_.Subject) + "</td><td class='mono'>" + (& $e $_.Detail) + '</td></tr>' }) -join ''
@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Live Watch - $(& $e $h.Computer)</title><style>
:root{--bg:#0d1211;--panel:#151c1a;--line:#26342f;--text:#d9dfe6;--dim:#8d99a6}body{background:var(--bg);color:var(--text);font:14px/1.5 Segoe UI,Arial,sans-serif;margin:0;padding:0 0 40px}.wrap{max-width:1100px;margin:0 auto;padding:0 20px}h1{margin:22px 0 2px;font-size:22px}h2{border-bottom:1px solid var(--line);padding-bottom:5px;margin:28px 0 10px;color:#3ddc84;font-size:16px}
table{border-collapse:collapse;width:100%}td,th{border:1px solid var(--line);padding:4px 8px;text-align:left;vertical-align:top;font-size:12.5px}th{background:var(--panel)}.dim{color:var(--dim)}.mono{font-family:Consolas,monospace;font-size:12px;word-break:break-all}
.tag{display:inline-block;padding:1px 8px;border-radius:9px;font-size:11px;font-weight:700;text-transform:uppercase;background:#2c3541}.tag.high{background:#8c2f2f;color:#fff}.tag.medium{background:#8a6a1b;color:#fff}.tag.low{background:#2d5a85;color:#fff}
</style></head><body><div class="wrap"><h1>$(Get-As4BirdSvg 30) Live Watch</h1><div class="dim">$(& $e $h.Computer) &middot; watched $Seconds s, checked every $Interval s &middot; $($Events.Count) events &middot; $(& $e $V.Verdict)</div>
<h2>Leads</h2><table>$fh</table><h2>Everything that appeared (UTC)</h2><table><tr><th>Time</th><th>What</th><th>Name</th><th>Detail</th></tr>$rows</table>
<p class="dim">Polling cannot see programs that start and end between two checks. Leads are for a person to confirm. Nothing on the machine was changed.</p></div></body></html>
"@
}

# ---------- snapshots ----------
function New-As4Snapshot {
    param([string]$Label = '', [scriptblock]$OnProgress)
    if (-not $global:Case) { throw 'No active case.' }
    $e = New-As4Entry 'snapshot' 'Snapshot of the machine state' $global:CaseFolders.Live
    Start-As4Run 'snapshot' | Out-Null; $files = @(); $path = $null
    try {
        $inv = Get-LhInventory -Light -OnProgress $OnProgress
        $by = @{}; foreach ($p in $inv.Processes) { $by[[int]$p.ProcessId] = $p }
        $ext = @($inv.Connections | Where-Object { $_.Proto -eq 'TCP' -and $_.State -eq 'Established' -and -not (Test-LhPrivateIp $_.RemoteAddress) } | ForEach-Object { $p = $by[[int]$_.ProcessId]; [pscustomobject]@{ Process = $(if ($p) { $p.Name } else { '?' }); Remote = "$($_.RemoteAddress):$($_.RemotePort)" } })
        $snap = [ordered]@{ Format = 'as4-snapshot-1'; Label = $Label; Taken = $inv.Taken; Computer = $env:COMPUTERNAME; User = "$env:USERDOMAIN\$env:USERNAME"; Admin = $inv.Admin; Errors = @($inv.Errors)
            Processes = @($inv.Processes | Select-Object Name, ExecutablePath, CommandLine); Services = $inv.Services; Drivers = $inv.Drivers; Tasks = $inv.Tasks; RunKeys = $inv.RunKeys; Startup = $inv.Startup; Wmi = $inv.Wmi
            Listening = @($inv.Connections | Where-Object { $_.State -eq 'Listen' } | ForEach-Object { $p = $by[[int]$_.ProcessId]; [pscustomobject]@{ Proto = $_.Proto; Port = $_.LocalPort; Process = $(if ($p) { $p.Name } else { '?' }) } })
            Peers = $ext; Users = $inv.Users; Admins = $inv.Admins; Software = $inv.Software; Hosts = $inv.Hosts }
        $path = Get-UniquePath (Get-CaseFolder 'Live') 'snapshot' 'json'; Write-As4File $path ($snap | ConvertTo-Json -Depth 6); $files += $path
        $e.Status = 'OK'; $e.Notes += "Snapshot saved: $($snap.Processes.Count) processes, $($snap.Services.Count) services, $($snap.Tasks.Count) tasks, $($snap.Software.Count) programs. Compare two snapshots to see what changed."
        $e.Command = 'powershell (in-process, read-only)'
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $out = Complete-As4Entry $e $files 'raw'; Stop-As4Run
    [pscustomobject]@{ Status = $out.Status; Notes = @($out.Notes); Path = $path }
}

function Get-As4Snapshots {
    param([string]$CaseDir)
    if (-not $CaseDir) { $CaseDir = $global:Case.Dir }
    $d = Join-Path $CaseDir $global:CaseFolders.Live
    if (-not (Test-Path -LiteralPath $d)) { return @() }
    Get-ChildItem -LiteralPath $d -Filter 'snapshot_*.json' -File | Sort-Object LastWriteTime | ForEach-Object { $l = ''; $c = ''; try { $j = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; $l = $j.Label; $c = $j.Taken } catch {}; [pscustomobject]@{ Path = $_.FullName; Name = $_.Name; Taken = $c; Label = $l } }
}

function Compare-As4Snapshots {
    param([Parameter(Mandatory)][string]$Before, [Parameter(Mandatory)][string]$After)
    $a = Get-Content -LiteralPath $Before -Raw | ConvertFrom-Json; $b = Get-Content -LiteralPath $After -Raw | ConvertFrom-Json
    $rows = New-Object Collections.ArrayList; $ind = Get-LhIndicators
    $sus = '(?i)powershell|pwsh|mshta|wscript|cscript|rundll32|regsvr32|cmd(\.exe)?\s+/c|\\Temp\\|\\Users\\Public\\|\\AppData\\|\\ProgramData\\'
    $diff = {
        param($cat, $x, $y, $keyf, $valf, $showf)
        $m1 = @{}; foreach ($i in @($x)) { $k = & $keyf $i; if ($k) { $m1[$k] = & $valf $i } }
        $m2 = @{}; foreach ($i in @($y)) { $k = & $keyf $i; if ($k) { $m2[$k] = & $valf $i } }
        foreach ($k in $m2.Keys) { if (-not $m1.ContainsKey($k)) { $lead = ''; if (("$k $($m2[$k])") -match $sus) { $lead = 'script host or writable folder' }; [void]$rows.Add([pscustomobject]@{ Category = $cat; Change = 'Added'; Item = $k; Detail = [string]$m2[$k]; Lead = $lead }) }
            elseif ($m1[$k] -ne $m2[$k]) { $lead = ''; if ([string]$m2[$k] -match $sus) { $lead = 'script host or writable folder' }; [void]$rows.Add([pscustomobject]@{ Category = $cat; Change = 'Changed'; Item = $k; Detail = "$($m1[$k])  ==>  $($m2[$k])"; Lead = $lead }) } }
        foreach ($k in $m1.Keys) { if (-not $m2.ContainsKey($k)) { [void]$rows.Add([pscustomobject]@{ Category = $cat; Change = 'Removed'; Item = $k; Detail = [string]$m1[$k]; Lead = '' }) } }
    }
    & $diff 'Programs running' $a.Processes $b.Processes { param($i) "$($i.Name) | $($i.ExecutablePath)" } { param($i) '' }
    & $diff 'Services' $a.Services $b.Services { param($i) $i.Name } { param($i) "$($i.State) | $($i.StartMode) | $($i.Account) | $($i.PathName)" }
    & $diff 'Drivers' $a.Drivers $b.Drivers { param($i) $i.Name } { param($i) $i.PathName }
    & $diff 'Scheduled tasks' $a.Tasks $b.Tasks { param($i) "$($i.TaskPath)$($i.TaskName)" } { param($i) "$($i.RunAs) | $($i.Actions)" }
    & $diff 'Autostart (registry)' $a.RunKeys $b.RunKeys { param($i) "$($i.Key)\$($i.Name)" } { param($i) $i.Value }
    & $diff 'Startup folders' $a.Startup $b.Startup { param($i) $i.FullName } { param($i) "$($i.Length) bytes" }
    & $diff 'WMI subscriptions' $a.Wmi $b.Wmi { param($i) "$($i.Class) $($i.Name)" } { param($i) $i.Detail }
    & $diff 'Listening ports' $a.Listening $b.Listening { param($i) "$($i.Proto) $($i.Port) $($i.Process)" } { param($i) '' }
    & $diff 'Internet peers' $a.Peers $b.Peers { param($i) "$($i.Process) -> $($i.Remote)" } { param($i) '' }
    & $diff 'Local users' $a.Users $b.Users { param($i) $i.Name } { param($i) "enabled=$($i.Enabled) passwordRequired=$($i.PasswordRequired)" }
    & $diff 'Administrators' $a.Admins $b.Admins { param($i) $i.Name } { param($i) '' }
    & $diff 'Installed programs' $a.Software $b.Software { param($i) $i.Name } { param($i) $i.Version }
    & $diff 'Hosts file' $a.Hosts $b.Hosts { param($i) $i.Line } { param($i) '' }
    # listed programs by tool name are called out
    foreach ($r in $rows) { if ($r.Change -eq 'Added') { $bn = (([string]$r.Item).ToLower() -replace '\.exe.*$', '' -replace '[\s-]+', '_'); foreach ($t in $ind.Tools) { if ($bn -match $t.Pattern) { $r.Lead = "$($t.Kind)"; break } } } }
    $rows
}

function Invoke-As4SnapshotCompare {
    param([string]$Before, [string]$After)
    if (-not $global:Case) { throw 'No active case.' }
    $e = New-As4Entry 'snapcompare' 'Snapshot comparison' $global:CaseFolders.Live
    Start-As4Run 'snapcompare' | Out-Null; $der = @(); $rows = @()
    try {
        $rows = @(Compare-As4Snapshots $Before $After)
        $dir = Get-CaseFolder 'Live'
        $csv = Get-UniquePath $dir 'snapshot_changes' 'csv'; Write-As4File $csv (($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"); $der += $csv
        $h = Get-UniquePath $dir 'SnapshotChanges' 'html'; Write-As4File $h (New-SnapHtml $rows $Before $After); $der += $h
        $leads = @($rows | Where-Object { $_.Lead -and $_.Change -ne 'Removed' }).Count
        $e.Status = 'OK'; $e.Notes += "$($rows.Count) difference(s), $leads with a lead. Before: $(Split-Path $Before -Leaf). After: $(Split-Path $After -Leaf)."
        $e.Command = 'powershell (in-process, offline)'
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $out = Complete-As4Entry $e @() 'derived'
    if ($der.Count) { Register-As4Files $der 'derived' | Out-Null }
    Stop-As4Run
    [pscustomobject]@{ Status = $out.Status; Notes = @($out.Notes); Rows = $rows; Html = $(if ($der.Count -gt 1) { $der[1] } else { $null }); Csv = $(if ($der.Count) { $der[0] } else { $null }) }
}

function New-SnapHtml {
    param($Rows, $Before, $After)
    $e = { param($s) HtmlEnc $s }
    $order = @{ Added = 0; Changed = 1; Removed = 2 }
    $tr = ($Rows | Sort-Object @{ e = { if ($_.Lead) { 0 } else { 1 } } }, Category, @{ e = { $order[$_.Change] } } | ForEach-Object { "<tr class='$($_.Change)'><td>" + (& $e $_.Category) + "</td><td><span class='tag $($_.Change)'>$($_.Change)</span></td><td class='mono'>" + (& $e $_.Item) + "</td><td class='mono'>" + (& $e $_.Detail) + "</td><td class='lead'>" + (& $e $_.Lead) + '</td></tr>' }) -join ''
@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>What changed</title><style>
:root{--bg:#0d1211;--panel:#151c1a;--line:#26342f;--text:#d9dfe6;--dim:#8d99a6}body{background:var(--bg);color:var(--text);font:14px/1.5 Segoe UI,Arial,sans-serif;margin:0;padding:0 0 40px}.wrap{max-width:1200px;margin:0 auto;padding:0 20px}h1{margin:22px 0 2px;font-size:22px}
table{border-collapse:collapse;width:100%;margin-top:10px}td,th{border:1px solid var(--line);padding:4px 8px;text-align:left;vertical-align:top;font-size:12.5px}th{background:var(--panel)}.dim{color:var(--dim)}.mono{font-family:Consolas,monospace;font-size:12px;word-break:break-all}
.tag{display:inline-block;padding:1px 8px;border-radius:9px;font-size:11px;font-weight:700;background:#2c3541}.tag.Added{background:#2d6a45;color:#fff}.tag.Removed{background:#6b3434;color:#fff}.tag.Changed{background:#8a6a1b;color:#fff}.lead{color:#f0c060}
</style></head><body><div class="wrap"><h1>$(Get-As4BirdSvg 30) What changed</h1><div class="dim">Before: $(& $e (Split-Path $Before -Leaf)) &middot; After: $(& $e (Split-Path $After -Leaf)) &middot; $($Rows.Count) difference(s). Rows with a lead are listed first.</div>
<table><tr><th>Area</th><th>Change</th><th>Item</th><th>Detail</th><th>Lead</th></tr>$tr</table>
<p class="dim">A difference is not a problem by itself: updates, new software and normal use change a machine. Look at the ones with a lead first.</p></div></body></html>
"@
}
