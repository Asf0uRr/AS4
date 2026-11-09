# AS4 IR Tool - Persistence

function Get-As4TriageTasks {
    @(
    (S 'tri_proctree' 'Process tree with hashes and signatures' 'Persist' {
        $ps = Get-CimInstance Win32_Process; $nm=@{}; $ps | ForEach-Object { $nm[[int]$_.ProcessId]=$_.Name }; $cache=@{}
        foreach ($p in $ps) {
            $path=$p.ExecutablePath; $h=$null; $sig=$null; $lead=@()
            if ($path -and (Test-Path -LiteralPath $path)) {
                if (-not $cache.ContainsKey($path)) { $x=$null; $s=$null; try { $x=(Get-As4Sha256 $path) } catch {}; try { $s=(Get-AuthenticodeSignature -LiteralPath $path).Status.ToString() } catch {}; $cache[$path]=@($x,$s) }
                $h=$cache[$path][0]; $sig=$cache[$path][1]
                if ($path -match '\\(Temp|AppData\\Local\\Temp|Users\\Public|ProgramData|Downloads|\$Recycle\.Bin)\\') { $lead+='runs from user-writable path' }
                if ($sig -and $sig -ne 'Valid') { $lead+="signature=$sig" }
            } elseif ($p.ProcessId -gt 4 -and -not $path) { $lead+='path not readable (protected or elevated needed)' }
            if ($p.Name -match '^(winword|excel|outlook|acrord32)\.exe$') { $kids=$ps | Where-Object { $_.ParentProcessId -eq $p.ProcessId -and $_.Name -match 'cmd|powershell|wscript|cscript|mshta|rundll32' }; if ($kids) { $lead+='office/reader spawned a shell/script host' } }
            [pscustomobject]@{ PID=$p.ProcessId; PPID=$p.ParentProcessId; Parent=$nm[[int]$p.ParentProcessId]; Name=$p.Name; Path=$path; Sha256=$h; Signature=$sig; CommandLine=$p.CommandLine; Created=$p.CreationDate; TriageLeads=($lead -join '; ') }
        } } 'Every process with parent, path, SHA-256 and Authenticode status. TriageLeads are heuristics only, not verdicts.' 'Starting point for suspicious-process triage.' -Admin 'partial' -Timeout 600)
    (S 'tri_services' 'Services with unusual binary paths' 'Persist' {
        Get-CimInstance Win32_Service | ForEach-Object { $path=$_.PathName; $lead=@()
            if ($path -match '(?i)\\(Temp|Users\\Public|ProgramData|AppData|Downloads)\\') { $lead+='binary in user-writable location' }
            if ($path -and $path -notmatch '^"' -and $path -match '^[A-Za-z]:\\[^"]*\s[^"]*\.exe' ) { $lead+='unquoted path with spaces' }
            if ($path -match '(?i)cmd(\.exe)?\s+/c|powershell|mshta|rundll32|regsvr32') { $lead+='service launches a shell/LOLBin' }
            [pscustomobject]@{ Name=$_.Name; State=$_.State; StartMode=$_.StartMode; Account=$_.StartName; PathName=$path; TriageLeads=($lead -join '; ') } } } 'Services flagged by simple path/launcher heuristics.' 'Malicious service installs.')
    (S 'tri_runkeys' 'Run / RunOnce registry entries' 'Persist' {
        $keys='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon','HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
        foreach ($k in $keys) { if (Test-Path $k) { $it=Get-Item $k; foreach ($n in $it.GetValueNames()) { [pscustomobject]@{ Key=$k; Name=$n; Value=[string]$it.GetValue($n); LastWriteNote='registry key last-write time requires hive parsing' } } } } } 'Autostart registry values for machine and current user. Other users'' hives are covered by registry-hive collection.' 'Classic persistence.' -Quick $true)
    (S 'tri_startupfolders' 'Startup folders' 'Persist' {
        $dirs=@("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"); Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $dirs+="$($_.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" }
        foreach ($d in $dirs) { if (Test-Path -LiteralPath $d) { Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Select-Object FullName,Length,CreationTimeUtc,LastWriteTimeUtc } } } 'Items in all-users and per-user Startup folders.' 'Persistence by dropped shortcut/script.' -Quick $true)
    (S 'tri_wmi' 'WMI event subscriptions' 'Persist' {
        foreach ($c in '__EventFilter','CommandLineEventConsumer','ActiveScriptEventConsumer','__FilterToConsumerBinding') { Get-CimInstance -Namespace root\subscription -ClassName $c -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Class=$c; Name=$_.Name; Query=$_.Query; CommandLineTemplate=$_.CommandLineTemplate; ScriptText=$_.ScriptText; Filter=[string]$_.Filter; Consumer=[string]$_.Consumer } } } } 'Permanent WMI subscriptions (filters, consumers, bindings). Zero records is a normal result.' 'Fileless persistence.' -Admin 'partial' -Quick $true)
    (S 'tri_tasks' 'Scheduled tasks - structured' 'Persist' {
        Get-ScheduledTask | ForEach-Object { $t=$_; $a=($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' | '; $lead=@(); if ($a -match '(?i)powershell|cmd\.exe|mshta|wscript|cscript|rundll32|regsvr32|\\Temp\\|\\AppData\\|\\Users\\Public\\') { $lead+='launches script host/LOLBin or user-writable path' }
            [pscustomobject]@{ TaskName=$t.TaskName; TaskPath=$t.TaskPath; State=$t.State; Author=$t.Author; RunAs=$t.Principal.UserId; Actions=$a; TriageLeads=($lead -join '; ') } } } 'All tasks with actions and heuristic leads.' 'Scheduled-task persistence.' -Quick $true)
    (S 'tri_defender' 'Defender detections and threat catalog' 'Persist' {
        Get-MpThreatDetection | Select-Object DetectionID,ThreatID,InitialDetectionTime,LastThreatStatusChangeTime,ProcessName,Resources,DomainUser,CleaningActionID,ActionSuccess; Get-MpThreat | Select-Object ThreatID,ThreatName,SeverityID,IsActive,DidThreatExecute,Resources } 'Recorded detections and threat metadata (read-only). Quarantined file contents are NOT extracted.' 'What Defender already saw.' -Quick $true)
    (S 'tri_recentexe' 'Recently created executables in writable locations (14 days)' 'Persist' {
        $since=(Get-Date).AddDays(-14); $roots="$env:ProgramData","$env:PUBLIC","$env:SystemRoot\Temp"; Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $roots+="$($_.FullName)\AppData","$($_.FullName)\Downloads","$($_.FullName)\Desktop" }
        foreach ($r in $roots) { if (Test-Path -LiteralPath $r) { Get-ChildItem -LiteralPath $r -Recurse -Force -File -Include *.exe,*.dll,*.ps1,*.bat,*.cmd,*.vbs,*.js,*.hta,*.scr,*.lnk,*.jar -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -gt $since -or $_.LastWriteTime -gt $since } | ForEach-Object { $sig=$null; if ($_.Extension -in '.exe','.dll') { try { $sig=(Get-AuthenticodeSignature -LiteralPath $_.FullName).Status.ToString() } catch {} }; [pscustomobject]@{ Path=$_.FullName; Size=$_.Length; CreatedUtc=$_.CreationTimeUtc.ToString('o'); ModifiedUtc=$_.LastWriteTimeUtc.ToString('o'); Signature=$sig } } } } } 'Executables/scripts created or modified in the last 14 days under ProgramData, Public, Temp and user AppData/Downloads/Desktop. Can be slow.' 'Dropped payloads.' -Timeout 900)
    (S 'tri_psactivity' 'PowerShell history and recent script-block hints' 'Persist' {
        Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $u=$_.Name; $f="$($_.FullName)\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"; if (Test-Path -LiteralPath $f) { $i=0; Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | ForEach-Object { $i++; $lead=''; if ($_ -match '(?i)-enc|FromBase64String|DownloadString|IEX|Invoke-Expression|bypass|hidden|Net\.WebClient') { $lead='suspicious keyword' }; [pscustomobject]@{ User=$u; Line=$i; Command=$_; TriageLeads=$lead } } } } } 'Per-user PSReadLine history (what users typed; may hold secrets). Raw files are also collected by the PowerShell artifact category.' 'Interactive attacker commands.' -Sensitive $true -Admin 'partial')
    (S 'tri_netsus' 'Network connections to external addresses' 'Persist' {
        $pn=@{}; Get-CimInstance Win32_Process | ForEach-Object { $pn[[int]$_.ProcessId]=$_.ExecutablePath }
        Get-NetTCPConnection -State Established | Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)' } | ForEach-Object { [pscustomobject]@{ Remote="$($_.RemoteAddress):$($_.RemotePort)"; LocalPort=$_.LocalPort; PID=$_.OwningProcess; Path=$pn[[int]$_.OwningProcess]; Created=$_.CreationTime } } } 'Established connections to non-private addresses with process path. No external lookups are made.' 'Candidate C2 - verify offline/with intel before concluding anything.' -Quick $true)
    )
}

function Get-As4TaskByIds { param([object[]]$Catalog, [string[]]$Ids) $Catalog | Where-Object { $Ids -contains $_.Id } }

# Autoruns (Sysinternals) if bundled and verified
function Invoke-Autoruns {
    $t = Get-As4Tool 'autorunsc'
    $e = New-As4Entry 'autoruns' 'Autoruns (autorunsc)' $global:CaseFolders.Persist
    Start-As4Run 'autoruns' | Out-Null; $files = @()
    try {
        if (-not $t -or -not $t.Path) { $e.Status = 'SKIPPED'; $e.Notes += 'autorunsc.exe not bundled (obtain from Sysinternals on the analyst workstation).'; return (Complete-As4Entry $e @()) }
        if ($t.Status -eq 'PRESENT_HASH_MISMATCH') { $e.Status = 'SKIPPED'; $e.Notes += 'Hash mismatch against manifest.'; return (Complete-As4Entry $e @()) }
        $a = @('-accepteula', '-a', '*', '-c', '-h', '-s', '-nobanner')
        $r = Invoke-As4Native -Exe $t.Path -Arguments $a -TimeoutSec 900
        $e.Command = $t.Path; $e.Arguments = $r.ArgString; $e.ExitCode = $r.ExitCode; $e.ToolVersion = $t.FileVersion
        $of = Get-UniquePath (Get-CaseFolder 'Persist') 'autoruns' 'csv'; Write-As4File $of $r.StdOut; $files += $of
        $e.Status = Get-As4OpStatusFromResult $r
        $e.Warnings += 'autorunsc -accepteula writes a EULA-accepted value to the registry (HKCU\Software\Sysinternals) on the target.'
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e $files; Stop-As4Run; $res
}
