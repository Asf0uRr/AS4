# AS4 IR Tool - Live Hunt: look at the running machine and say what deserves attention. ASCII only.
# Read-only. Nothing is stopped, changed, deleted or sent anywhere. Rules live in config\profiles\live_indicators.json.

$global:LhInd = $null
$global:LhSig = @{}
$global:LhUserWritable = '(?i)\\(Temp|AppData|Users\\Public|ProgramData|Downloads|\$Recycle\.Bin|PerfLogs)(\\|$)'
$global:LhHighRisk = '(?i)\\(Temp|Users\\Public|Downloads|\$Recycle\.Bin|PerfLogs)(\\|$)'

function Get-LhIndicators {
    if (-not $global:LhInd) { $f = Join-Path $global:P.Profiles 'live_indicators.json'; if (-not (Test-Path -LiteralPath $f)) { throw "Missing $f" }; $global:LhInd = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json }
    $global:LhInd
}

function New-LhFinding {
    param([string]$Sev, [string]$Area, [string]$Title, [string]$Detail, [string]$Mitre = '', [string]$Why = '', [string]$Next = '', [string]$Pid0 = '')
    [pscustomobject]@{ Sev = $Sev; Area = $Area; Title = $Title; Detail = $Detail; Mitre = $Mitre; Why = $Why; Next = $Next; ProcessId = $Pid0 }
}

function Test-LhPrivateIp {
    param([string]$Ip)
    if (-not $Ip) { return $true }
    $Ip = $Ip -replace '%.*$', ''
    if ($Ip -match '^::ffff:(\d+\.\d+\.\d+\.\d+)$') { $Ip = $Matches[1] }
    if ($Ip -match ':') { return ($Ip -eq '::' -or $Ip -eq '::1' -or $Ip -match '^(?i)(fe[89ab]|f[cd]|ff)') }
    ($Ip -match '^(0\.|10\.|127\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|22[4-9]\.|23\d\.|24\d\.|25[0-5]\.)')
}

# gentle mode: servers (and busy machines) get longer pauses, no file scan and smaller event reads
$global:LhGentle = $null
function Test-LhGentle {
    if ($null -ne $global:LhGentle) { return $global:LhGentle }
    $g = ($env:AS4_GENTLE -eq '1')
    try { $os = Get-CimInstance Win32_OperatingSystem -Property ProductType -ErrorAction Stop; if ([int]$os.ProductType -ne 1) { $g = $true } } catch {}
    try { $cpu = (Get-CimInstance Win32_Processor -Property LoadPercentage -ErrorAction Stop | Measure-Object LoadPercentage -Average).Average; if ($cpu -gt 75) { $g = $true } } catch {}
    $global:LhGentle = $g; $g
}
function Invoke-LhPause { param([int]$Ms = 10) if (Test-LhGentle) { $Ms = $Ms * 4 }; Start-Sleep -Milliseconds $Ms; if ($global:UiPump) { & $global:UiPump } }

function Get-LhSig {
    # Authenticode status of a file, cached. Uses the Windows verifier on this machine.
    param([string]$Path)
    if (-not $Path) { return [pscustomobject]@{ Status = 'Unknown'; Signer = '' } }
    $k = $Path.ToLower(); if ($global:LhSig.ContainsKey($k)) { return $global:LhSig[$k] }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $r = [pscustomobject]@{ Status = 'Missing'; Signer = '' } }
    else {
        try { $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop; $sg = ''; if ($s.SignerCertificate) { $sg = ($s.SignerCertificate.Subject -replace '^.*?CN="?([^,"]+).*$', '$1') }; $r = [pscustomobject]@{ Status = [string]$s.Status; Signer = $sg } }
        catch { $r = [pscustomobject]@{ Status = 'Error'; Signer = '' } }
    }
    $global:LhSig[$k] = $r; Invoke-LhPause 8; $r
}

function Get-LhDistance {
    param([string]$a, [string]$b)
    $m = $a.Length; $n = $b.Length; if (-not $m) { return $n }; if (-not $n) { return $m }
    $d = New-Object 'int[,]' ($m + 1), ($n + 1)
    for ($i = 0; $i -le $m; $i++) { $d[$i, 0] = $i }; for ($j = 0; $j -le $n; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $m; $i++) { for ($j = 1; $j -le $n; $j++) { $c = 1; if ($a[$i - 1] -eq $b[$j - 1]) { $c = 0 }; $im = $i - 1; $jm = $j - 1; $x1 = $d[$im, $j] + 1; $x2 = $d[$i, $jm] + 1; $x3 = $d[$im, $jm] + $c; $m1 = [Math]::Min($x1, $x2); $d[$i, $j] = [Math]::Min($m1, $x3) } }
    $d[$m, $n]
}

function Get-LhExePath {
    # pulls the program path out of a service or Run-key command line
    param([string]$Cmd)
    if (-not $Cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Cmd.Trim())
    if ($c -match '^"([^"]+)"') { return $Matches[1] }
    if ($c -match '^([A-Za-z]:\\.*?\.(exe|dll|sys|bat|cmd|ps1|vbs|js|scr|com))(\s|$)') { return $Matches[1] }
    if ($c -match '^(\S+)') { return $Matches[1] }
    $null
}

function Get-LhDescendants {
    # PIDs of this process and everything it started, so AS4 never flags itself
    param($ByPid)
    $set = New-Object 'System.Collections.Generic.HashSet[int]'; [void]$set.Add([int]$PID)
    $changed = $true; $guard = 0
    while ($changed -and $guard -lt 20) { $changed = $false; $guard++; foreach ($k in @($ByPid.Keys)) { $pp = [int]$ByPid[$k].ParentProcessId; if ($set.Contains($pp) -and -not $set.Contains([int]$k)) { [void]$set.Add([int]$k); $changed = $true } } }
    , $set
}

# ---------- what is on the machine ----------
function Get-LhInventory {
    param([switch]$Light, [scriptblock]$OnProgress)
    $inv = [ordered]@{ Taken = (Get-UtcIso); Errors = New-Object Collections.ArrayList; Admin = (Test-As4Admin) }
    $step = 0; $total = $(if ($Light) { 12 } else { 19 })
    $run = { param($name, $sb)
        $global:LhStep++
        if ($OnProgress) { & $OnProgress $global:LhStep $total "Reading $name" }
        try { $inv[$name] = @(& $sb) } catch { $inv[$name] = @(); [void]$inv.Errors.Add("${name}: $($_.Exception.Message)") } }
    $global:LhStep = 0
    & $run 'Processes' { Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine, CreationDate -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ ProcessId = [int]$_.ProcessId; ParentProcessId = [int]$_.ParentProcessId; Name = [string]$_.Name; ExecutablePath = [string]$_.ExecutablePath; CommandLine = [string]$_.CommandLine; Created = $(if ($_.CreationDate) { $_.CreationDate.ToUniversalTime().ToString('o') } else { '' }) } } }
    & $run 'Connections' {
        $r = @(); foreach ($c in (Get-NetTCPConnection -ErrorAction Stop | Where-Object { $_.State -in 'Established', 'Listen', 'SynSent', 'CloseWait' })) { $r += [pscustomobject]@{ Proto = 'TCP'; State = [string]$c.State; LocalAddress = [string]$c.LocalAddress; LocalPort = [int]$c.LocalPort; RemoteAddress = [string]$c.RemoteAddress; RemotePort = [int]$c.RemotePort; ProcessId = [int]$c.OwningProcess } }
        foreach ($u in @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue)) { $r += [pscustomobject]@{ Proto = 'UDP'; State = 'Listen'; LocalAddress = [string]$u.LocalAddress; LocalPort = [int]$u.LocalPort; RemoteAddress = ''; RemotePort = 0; ProcessId = [int]$u.OwningProcess } }
        $r }
    & $run 'Services' { Get-CimInstance Win32_Service -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; DisplayName = [string]$_.DisplayName; State = [string]$_.State; StartMode = [string]$_.StartMode; Account = [string]$_.StartName; PathName = [string]$_.PathName; ProcessId = [int]$_.ProcessId } } }
    & $run 'Drivers' { Get-CimInstance Win32_SystemDriver -ErrorAction Stop | Where-Object { $_.State -eq 'Running' } | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; PathName = [string]$_.PathName; StartMode = [string]$_.StartMode } } }
    & $run 'Tasks' { Get-ScheduledTask -ErrorAction Stop | ForEach-Object { $t = $_; [pscustomobject]@{ TaskName = [string]$t.TaskName; TaskPath = [string]$t.TaskPath; State = [string]$t.State; Author = [string]$t.Author; RunAs = [string]$t.Principal.UserId; Hidden = [bool]$t.Settings.Hidden; Actions = (($t.Actions | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() }) -join ' | ') } } }
    & $run 'RunKeys' {
        foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run') {
            if (Test-Path -LiteralPath $k) { $it = Get-Item -LiteralPath $k; foreach ($n in $it.GetValueNames()) { [pscustomobject]@{ Key = $k; Name = $n; Value = [string]$it.GetValue($n) } } } } }
    & $run 'Startup' {
        $dirs = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"); Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $dirs += "$($_.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" }
        foreach ($d in $dirs) { if (Test-Path -LiteralPath $d -ErrorAction SilentlyContinue) { Get-ChildItem -LiteralPath $d -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object { [pscustomobject]@{ FullName = $_.FullName; Length = $_.Length; CreatedUtc = $_.CreationTimeUtc.ToString('o') } } } } }
    & $run 'Wmi' { foreach ($c in '__EventFilter', 'CommandLineEventConsumer', 'ActiveScriptEventConsumer', '__FilterToConsumerBinding') { Get-CimInstance -Namespace root\subscription -ClassName $c -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Class = $c; Name = [string]$_.Name; Detail = (@([string]$_.Query, [string]$_.CommandLineTemplate, [string]$_.ScriptText, [string]$_.Filter, [string]$_.Consumer) | Where-Object { $_ }) -join ' ; ' } } } }
    & $run 'Users' { Get-LocalUser -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Enabled = [bool]$_.Enabled; PasswordRequired = [bool]$_.PasswordRequired; Sid = [string]$_.SID.Value; LastLogon = $(if ($_.LastLogon) { $_.LastLogon.ToUniversalTime().ToString('o') } else { '' }) } } }
    & $run 'Admins' {
        $r = @(); try { $r = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Type = [string]$_.ObjectClass; Source = [string]$_.PrincipalSource } }) }
        catch { $gn = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]; $o = & net.exe localgroup $gn 2>$null; $on = $false; foreach ($l in $o) { if ($l -match '^-{5,}') { $on = $true; continue }; if ($on -and $l.Trim() -and $l -notmatch '^(The command|Der Befehl)') { $r += [pscustomobject]@{ Name = $l.Trim(); Type = ''; Source = '' } } } }
        $r }
    & $run 'Software' {
        foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
            Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object { [pscustomobject]@{ Name = [string]$_.DisplayName; Version = [string]$_.DisplayVersion; Publisher = [string]$_.Publisher; InstallDate = [string]$_.InstallDate } } } }
    & $run 'Hosts' { $h = "$env:SystemRoot\System32\drivers\etc\hosts"; if (Test-Path -LiteralPath $h) { Get-Content -LiteralPath $h -ErrorAction Stop | Where-Object { $_.Trim() -and $_.Trim() -notmatch '^#' } | ForEach-Object { [pscustomobject]@{ Line = $_.Trim() } } } }
    if (-not $Light) {
        & $run 'Posture' {
            $g = { param($p, $n) try { (Get-ItemProperty -LiteralPath $p -Name $n -ErrorAction Stop).$n } catch { $null } }
            $o = [ordered]@{}
            $o.RdpEnabled = $(try { (& $g 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') -eq 0 } catch { $false })
            $o.RdpNla = & $g 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication'
            $o.RdpPort = & $g 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'PortNumber'
            $o.Uac = & $g 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
            $o.TokenFilter = & $g 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'LocalAccountTokenFilterPolicy'
            $o.WDigest = & $g 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential'
            $o.LsaPpl = & $g 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL'
            $o.Smb1 = & $g 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1'
            $o.DefenderOff = & $g 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiSpyware'
            $o.DefenderRtOff = & $g 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableRealtimeMonitoring'
            $o.ScriptBlockLogging = & $g 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging'
            $o.CmdLineAudit = & $g 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' 'ProcessCreationIncludeCmdLine_Enabled'
            $o.ProxyEnable = & $g 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyEnable'
            $o.ProxyServer = & $g 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' 'ProxyServer'
            $o.AutoConfigUrl = & $g 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' 'AutoConfigURL'
            $o.TimeZone = [TimeZoneInfo]::Local.Id
            $ppl = New-Object Collections.ArrayList; try { $pp = Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\PortProxy4tov4	cp' -ErrorAction Stop; foreach ($n in $pp.GetValueNames()) { [void]$ppl.Add("$n -> $($pp.GetValue($n))") } } catch {}
            $o.PortProxy = $ppl.ToArray()
            $dnl = New-Object Collections.ArrayList; try { foreach ($x in (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop)) { foreach ($a in $x.ServerAddresses) { if ($a -and -not $dnl.Contains($a)) { [void]$dnl.Add($a) } } } } catch {}
            $o.Dns = $dnl.ToArray()
            [pscustomobject]$o }
        & $run 'Defender' {
            $o = [ordered]@{ Available = $false }
            try { $s = Get-MpComputerStatus -ErrorAction Stop; $o.Available = $true; $o.RealTime = [bool]$s.RealTimeProtectionEnabled; $o.AntiVirus = [bool]$s.AntivirusEnabled; $o.Tamper = [bool]$s.IsTamperProtected; $o.SignatureUpdated = $(if ($s.AntivirusSignatureLastUpdated) { $s.AntivirusSignatureLastUpdated.ToUniversalTime().ToString('o') } else { '' }) } catch {}
            try { $m = Get-MpPreference -ErrorAction Stop; $o.ExclusionPath = @($m.ExclusionPath | Where-Object { $_ }); $o.ExclusionProcess = @($m.ExclusionProcess | Where-Object { $_ }); $o.ExclusionExtension = @($m.ExclusionExtension | Where-Object { $_ }) } catch {}
            [pscustomobject]$o }
        & $run 'AntiVirus' { Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { $st = ([int]$_.productState -band 0xF000) -shr 12; [pscustomobject]@{ Name = [string]$_.displayName; State = $(switch ($st) { 0 { 'off' } 1 { 'on' } 2 { 'snoozed' } 3 { 'expired' } default { 'unknown' } }); Active = ($st -eq 1) } } }
        & $run 'Firewall' { Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Enabled = [bool]($_.Enabled -eq 'True' -or $_.Enabled -eq 1) } } }
        & $run 'Pipes' { [IO.Directory]::GetFiles('\\.\pipe\') | ForEach-Object { $_.Substring($_.LastIndexOf('\') + 1) } | ForEach-Object { [pscustomobject]@{ Name = $_ } } }
        & $run 'Prefetch' { if ($inv.Admin -and (Test-Path "$env:SystemRoot\Prefetch")) { Get-ChildItem "$env:SystemRoot\Prefetch\*.pf" -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ File = $_.Name; Program = ($_.Name -replace '-[0-9A-F]{8}\.pf$', ''); LastWriteUtc = $_.LastWriteTimeUtc.ToString('o') } } } }
        & $run 'LogChannels' {
            $ind = Get-LhIndicators
            foreach ($c in $ind.LogChannels) {
                $row = [ordered]@{ Channel = $c.Name; Use = $c.Use; Exists = $false; Enabled = $false; Records = 0; Oldest = ''; Newest = ''; NeedsAdmin = [bool]$c.Admin; Note = '' }
                try { $l = Get-WinEvent -ListLog $c.Name -ErrorAction Stop; $row.Exists = $true; $row.Enabled = [bool]$l.IsEnabled; $row.Records = [int64]$l.RecordCount
                    if ($row.Records -gt 0) { try { $o = Get-WinEvent -LogName $c.Name -Oldest -MaxEvents 1 -ErrorAction Stop; $row.Oldest = $o.TimeCreated.ToUniversalTime().ToString('o') } catch { $row.Note = 'cannot read (needs administrator?)' }
                        try { $n = Get-WinEvent -LogName $c.Name -MaxEvents 1 -ErrorAction Stop; $row.Newest = $n.TimeCreated.ToUniversalTime().ToString('o') } catch {} } } catch { $row.Note = 'not present on this machine' }
                [pscustomobject]$row } }
    }
    $inv
}

# ---------- one process against the rules (also used by Live Watch) ----------
function Test-LhProcess {
    param($P, $ByPid, $Skip)
    $ind = Get-LhIndicators; $f = New-Object Collections.ArrayList
    if ($Skip -and $Skip.Contains([int]$P.ProcessId)) { return @() }
    $name = ([string]$P.Name).ToLower(); $path = [string]$P.ExecutablePath; $cmd = [string]$P.CommandLine; $label = "$($P.Name) (PID $($P.ProcessId))"
    $pp = $null; if ($ByPid.ContainsKey([int]$P.ParentProcessId)) { $pp = $ByPid[[int]$P.ParentProcessId]; if ($pp.Created -and $P.Created -and [string]$pp.Created -gt [string]$P.Created) { $pp = $null } }   # PID reuse: a parent cannot be younger than its child
    $parentName = ''; if ($pp) { $parentName = ([string]$pp.Name).ToLower() }
    $sys32 = (Join-Path $env:SystemRoot 'System32')
    $detail = { param($x) $s = $x; if ($path) { $s += " | $path" }; if ($pp) { $s += " | started by $($pp.Name) (PID $($pp.ProcessId))" }; $s }
    # core Windows processes: right folder, right parent
    $sp = $ind.SystemProcesses.PSObject.Properties[$name]
    if ($sp) {
        if ($path -and -not $path.StartsWith($sys32 + '\', [StringComparison]::OrdinalIgnoreCase)) { [void]$f.Add((New-LhFinding 'high' 'Processes' 'Windows system process running from the wrong folder' (& $detail "$label should live in System32") 'T1036.005' 'Attackers name their program like a core Windows process so it blends in. The real one only runs from System32.' 'Hash the file, check its signature, and look at how it was started.' $P.ProcessId)) }
        $exp = [string]$sp.Value.Parent
        if ($exp -eq 'system') { if ($parentName -notin '', 'system', 'smss.exe') { [void]$f.Add((New-LhFinding 'high' 'Processes' 'Windows system process with an unexpected parent' (& $detail "$label expected parent: System/smss.exe") 'T1036.005' 'Core Windows processes always start the same way. A different parent is a classic sign of impersonation.' 'Compare with a clean machine of the same Windows version.' $P.ProcessId)) } }
        elseif ($exp -eq '') { if ($pp -and $parentName -ne 'smss.exe') { [void]$f.Add((New-LhFinding 'medium' 'Processes' 'Windows system process with an unexpected parent' (& $detail "$label normally has no live parent") 'T1036.005' 'Core Windows processes always start the same way.' 'Compare with a clean machine of the same Windows version.' $P.ProcessId)) } }
        elseif ($parentName -ne $exp -and -not ($parentName -eq '' -and $name -in 'taskhostw.exe', 'runtimebroker.exe', 'dwm.exe')) { [void]$f.Add((New-LhFinding 'high' 'Processes' 'Windows system process with an unexpected parent' (& $detail "$label expected parent: $exp") 'T1036.005' 'Core Windows processes always start the same way. A different parent is a classic sign of impersonation.' 'Compare with a clean machine of the same Windows version.' $P.ProcessId)) }
    } elseif ($name -match '\.exe$') {
        # names that imitate a Windows process
        $b = $name -replace '\.exe$', ''
        if ($b.Length -ge 5 -and $ind.LookalikeOf -notcontains $name -and $ind.LookalikeAllow -notcontains $name) {
            foreach ($t in $ind.LookalikeOf) { $tb = $t -replace '\.exe$', ''; if ([Math]::Abs($tb.Length - $b.Length) -le 1) { $dist = Get-LhDistance $b $tb; if ($dist -ge 1 -and ($dist -le 1 -or ($dist -le 2 -and $b.Length -ge 7))) {
                $sg = Get-LhSig $path; $sv = 'high'; if ($sg.Status -eq 'Valid' -or -not $path) { $sv = 'low' }
                [void]$f.Add((New-LhFinding $sv 'Processes' 'Program name looks like a Windows process' (& $detail "$label resembles $t") 'T1036.004' 'A one-letter difference from a well-known name is a common disguise.' 'Check the file path, signature and what started it.' $P.ProcessId)); break } } } }
    }
    # where the file is, and is it signed
    if ($path) {
        # ordinary System32 programs are not signature-checked (saves CPU on busy machines); core Windows processes always are
        if (-not $sp -and ($path.StartsWith($sys32 + '\', [StringComparison]::OrdinalIgnoreCase) -or ((Test-LhGentle) -and $path -match '(?i)^[A-Za-z]:\\(Program Files( \(x86\))?|Windows)\\'))) { $sg = [pscustomobject]@{ Status = 'Valid'; Signer = '' } } else { $sg = Get-LhSig $path }
        if ($sg.Status -eq 'Missing') { $sv = 'medium'; if ($path -match $global:LhUserWritable) { $sv = 'high' }; [void]$f.Add((New-LhFinding $sv 'Processes' 'Running program whose file is gone from disk' (& $detail $label) 'T1070.004' 'The file was deleted after it started. Some installers do this; malware does it to hide.' 'Capture memory and recover the file from memory or from a backup or shadow copy.' $P.ProcessId)) }
        elseif ($sg.Status -in 'HashMismatch', 'NotTrusted') { [void]$f.Add((New-LhFinding 'high' 'Processes' 'Program with an invalid digital signature' (& $detail "$label signature: $($sg.Status)") 'T1553.002' 'The file claims to be signed but the signature does not verify. It may have been modified.' 'Hash the file and compare with a known good copy.' $P.ProcessId)) }
        elseif ($path -match $global:LhHighRisk -and $sg.Status -ne 'Valid') { [void]$f.Add((New-LhFinding 'high' 'Processes' 'Unsigned program running from a temporary or shared folder' (& $detail $label) 'T1204.002' 'Temp, Downloads and Public folders are where dropped payloads usually run from.' 'Hash it, check it on your intelligence source, and see what started it.' $P.ProcessId)) }
        elseif ($path -match $global:LhUserWritable -and $sg.Status -ne 'Valid') { [void]$f.Add((New-LhFinding 'medium' 'Processes' 'Unsigned program running from AppData or ProgramData' (& $detail $label) 'T1204.002' 'Writable folders let any user drop a program; legitimate apps there are usually signed.' 'Check the vendor and the file creation time.' $P.ProcessId)) }
        elseif ($sg.Status -eq 'NotSigned' -and $path.StartsWith($env:SystemRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { [void]$f.Add((New-LhFinding 'medium' 'Processes' 'Unsigned program inside the Windows folder' (& $detail $label) 'T1036' 'Windows files are signed. An unsigned one in the Windows folder is unusual.' 'Compare with a clean machine.' $P.ProcessId)) }
    }
    # who started it
    foreach ($k in $ind.ShellSpawners.PSObject.Properties) { if ($parentName -match $k.Value -and $name -match $ind.ShellNames) { $sv = 'high'; if ($k.Name -eq 'Script hosts') { $sv = 'medium' }
        [void]$f.Add((New-LhFinding $sv 'Processes' "$($k.Name) started a shell or script program" (& $detail "$($pp.Name) -> $($P.Name)") 'T1059' 'Documents, readers and web servers do not normally open command shells. This is how macros and web shells run commands.' 'Find the document or web request that started it.' $P.ProcessId)) } }
    # what it was asked to do
    if ($cmd) { foreach ($c in $ind.CommandLines) { if ($cmd -match $c.Pattern) { $short = $cmd; if ($short.Length -gt 240) { $short = $short.Substring(0, 240) + '...' }
        [void]$f.Add((New-LhFinding $c.Sev 'Processes' $c.Title (& $detail "$label : $short") $c.Mitre $c.Why $c.Next $P.ProcessId)) } } }
    # known attack and dual-use tool names
    $bn = ($name -replace '\.exe$', '') -replace '[\s-]+', '_'
    foreach ($t in $ind.Tools) { if ($bn -match $t.Pattern) { [void]$f.Add((New-LhFinding $t.Sev 'Tools' "$($t.Kind): $($P.Name)" (& $detail $label) $t.Mitre 'The program name matches software used by attackers. Some of it is also used by administrators.' 'Decide whether it is authorised here. Find who started it and when it was installed.' $P.ProcessId)); break } }
    @($f)
}

function Test-LhProcesses {
    param($Inv)
    $f = New-Object Collections.ArrayList; $ind = Get-LhIndicators
    $by = @{}; foreach ($p in $Inv.Processes) { $by[[int]$p.ProcessId] = $p }
    $skip = Get-LhDescendants $by
    foreach ($p in $Inv.Processes) { foreach ($x in @(Test-LhProcess $p $by $skip)) { [void]$f.Add($x) } }
    foreach ($sp in $ind.SystemProcesses.PSObject.Properties) { if ($sp.Value.Single) { $n = @($Inv.Processes | Where-Object { $_.Name -ieq $sp.Name }).Count; if ($n -gt 1) { [void]$f.Add((New-LhFinding 'high' 'Processes' 'More than one copy of a process that should run once' "$($sp.Name) is running $n times" 'T1036.005' 'Windows starts exactly one instance. A second one is often an imitation.' 'Compare their paths, parents and start times.')) } } }
    $hidden = @($Inv.Processes | Where-Object { -not $_.ExecutablePath -and $_.ProcessId -gt 4 -and $_.Name -notmatch '^(Registry|Memory Compression|Secure System|vmmem.*|System|Idle)$' })
    if ($hidden.Count -gt 5 -and -not $Inv.Admin) { [void]$f.Add((New-LhFinding 'info' 'Coverage' 'Paths of some processes are not visible' "$($hidden.Count) processes belong to other users or the system; run as administrator to see them" '' 'Without administrator rights Windows hides the path and command line of other accounts'' processes.' 'Run again as administrator for a complete view.')) }
    @($f)
}

function Test-LhNetwork {
    param($Inv)
    $f = New-Object Collections.ArrayList; $ind = Get-LhIndicators
    $by = @{}; foreach ($p in $Inv.Processes) { $by[[int]$p.ProcessId] = $p }
    $skip = Get-LhDescendants $by
    foreach ($c in $Inv.Connections) {
        $p = $by[[int]$c.ProcessId]; if ($skip.Contains([int]$c.ProcessId)) { continue }
        $pn = if ($p) { ([string]$p.Name).ToLower() } else { '' }; $path = if ($p) { [string]$p.ExecutablePath } else { '' }; $lab = if ($p) { "$($p.Name) (PID $($p.ProcessId))" } else { "PID $($c.ProcessId)" }
        if ($c.Proto -eq 'TCP' -and $c.State -in 'Established', 'SynSent' -and -not (Test-LhPrivateIp $c.RemoteAddress)) {
            $to = "$($c.RemoteAddress):$($c.RemotePort)"
            if ($pn -and $ind.NoNetworkExpected -contains $pn) { [void]$f.Add((New-LhFinding 'high' 'Network' 'Program that rarely uses the network is connected to the internet' "$lab -> $to ($($c.State))" 'T1071' 'Calculators, editors and script helpers do not normally talk to the internet. Attackers use them as a cover for code they inject or load.' 'Capture memory and check what is loaded in the process.' $c.ProcessId)); continue }
            if ($path) { $sg = Get-LhSig $path
                if ($sg.Status -ne 'Valid' -and $path -match $global:LhHighRisk) { [void]$f.Add((New-LhFinding 'high' 'Network' 'Unsigned program from a temporary folder is talking to the internet' "$lab ($path) -> $to" 'T1071' 'A program that was dropped in a temp folder and now talks to the internet fits a payload calling home.' 'Note the address, hash the file, and block or monitor it according to your procedure.' $c.ProcessId)); continue }
                if ($sg.Status -ne 'Valid' -and $path -match $global:LhUserWritable) { [void]$f.Add((New-LhFinding 'medium' 'Network' 'Unsigned program from AppData or ProgramData is talking to the internet' "$lab ($path) -> $to" 'T1071' 'Unsigned software in user-writable folders that connects out deserves a look.' 'Note the address and check the vendor.' $c.ProcessId)); continue } }
            if ($c.RemotePort -in 4444, 4445, 1337, 31337, 5555, 6666, 6667, 9001, 9050, 8333) { [void]$f.Add((New-LhFinding 'medium' 'Network' 'Connection to a port often used by backdoors or Tor' "$lab -> $to" 'T1571' 'These port numbers are common defaults of remote access tools and anonymity networks.' 'Check the process and the destination.' $c.ProcessId)) }
        }
        if ($c.State -eq 'Listen' -and $c.LocalAddress -notin '127.0.0.1', '::1' -and $path) { $sg = Get-LhSig $path; if ($sg.Status -ne 'Valid' -and $path -match $global:LhUserWritable) { [void]$f.Add((New-LhFinding 'medium' 'Network' 'Unsigned program from a writable folder is listening for connections' "$lab listens on $($c.LocalAddress):$($c.LocalPort) ($($c.Proto))" 'T1090' 'A listener from a user-writable folder can be a backdoor or a proxy.' 'Check whether the port is reachable from other machines.' $c.ProcessId)) } }
    }
    @($f)
}

function Test-LhServices {
    param($Inv)
    $f = New-Object Collections.ArrayList
    foreach ($s in $Inv.Services) {
        $pn = [string]$s.PathName; if (-not $pn) { continue }; $exe = Get-LhExePath $pn; $lab = "$($s.Name) ($($s.State), $($s.StartMode), $($s.Account))"
        if ($pn -match '(?i)^\s*"?(cmd|powershell|pwsh|mshta|wscript|cscript|rundll32|regsvr32)(\.exe)?"?\s' -or $pn -match '(?i)cmd(\.exe)?\s+/c') { [void]$f.Add((New-LhFinding 'high' 'Services' 'Service that launches a command shell or script host' "$lab : $pn" 'T1543.003' 'Real services are programs. A service that runs a shell command is how PsExec-style tools and some malware run.' 'Check the service install time in the System log (event 7045).')); continue }
        if ($exe -and $exe -match $global:LhUserWritable) { $sg = Get-LhSig $exe; if ($sg.Status -ne 'Valid') { $sv = 'medium'; if ($exe -match $global:LhHighRisk) { $sv = 'high' }; [void]$f.Add((New-LhFinding $sv 'Services' 'Service whose program is unsigned and in a writable folder' "$lab : $pn" 'T1543.003' 'Services run with high rights. A program in a folder any user can write to is a risk.' 'Check the file creation time and who installed it.')) } }
        elseif ($pn -notmatch '^"' -and $pn -match '^[A-Za-z]:\\[^"]*\s[^"]*\.exe' -and $pn -notmatch '(?i)^[A-Za-z]:\\Windows\\') { [void]$f.Add((New-LhFinding 'low' 'Services' 'Service path with spaces and no quotes' "$lab : $pn" 'T1574.009' 'An unquoted path can let a user plant a program that runs with the service''s rights.' 'Fix is a configuration change for the system owner; AS4 does not change anything.')) }
        if ($pn -match '(?i)svchost' ) { try { $dll = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)\Parameters" -Name ServiceDll -ErrorAction Stop).ServiceDll; $dp = [Environment]::ExpandEnvironmentVariables([string]$dll)
            if ($dp -and -not $dp.StartsWith($env:SystemRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { $sg = Get-LhSig $dp; if ($sg.Status -ne 'Valid') { $sv = 'medium'; if ($dp -match $global:LhUserWritable) { $sv = 'high' }; [void]$f.Add((New-LhFinding $sv 'Services' 'Service DLL outside Windows and not validly signed' "$($s.Name) loads $dp" 'T1543.003' 'A DLL loaded by svchost runs inside a trusted process. Outside the Windows folder and unsigned is unusual.' 'Hash the DLL and check its origin.')) } } } catch {} }
    }
    foreach ($d in $Inv.Drivers) { $p = [string]$d.PathName; if (-not $p) { continue }; $p = $p -replace '^\\\?\?\\', '' -replace '^\\SystemRoot', $env:SystemRoot
        if ($p -notmatch '(?i)\\System32\\(drivers|DriverStore)\\|\\System32\\ntoskrnl|\\System32\\(win32k|hal|CI|clfs|ksecdd)') { $sg = Get-LhSig $p; if ($sg.Status -notin 'Valid', 'Missing') { [void]$f.Add((New-LhFinding 'high' 'Services' 'Loaded kernel driver that is not validly signed' "$($d.Name) : $p ($($sg.Status))" 'T1014' 'Unsigned drivers in kernel memory can hide processes and files.' 'Capture memory and examine the driver file.')) } } }
    @($f)
}

function Test-LhPersistence {
    param($Inv)
    $f = New-Object Collections.ArrayList; $ind = Get-LhIndicators
    $susCmd = '(?i)powershell|pwsh|mshta|wscript|cscript|rundll32|regsvr32|cmd(\.exe)?\s+/c|-enc\b|-encodedcommand|bitsadmin|certutil|\\Temp\\|\\Users\\Public\\'
    foreach ($r in $Inv.RunKeys) { $exe = Get-LhExePath $r.Value; $lab = "$($r.Key)\$($r.Name) = $($r.Value)"
        if ($r.Value -match $susCmd) { [void]$f.Add((New-LhFinding 'medium' 'Persistence' 'Autostart entry that runs a script host or temp file' $lab 'T1547.001' 'Programs listed here start at every logon. Script hosts and temp paths are typical of malware.' 'Open the target file and check who created the key.')); continue }
        if ($exe -and $exe -match $global:LhUserWritable) { $sg = Get-LhSig $exe; if ($sg.Status -ne 'Valid') { $sv = 'medium'; if ($exe -match $global:LhHighRisk) { $sv = 'high' }; [void]$f.Add((New-LhFinding $sv 'Persistence' 'Autostart entry points to an unsigned program in a writable folder' $lab 'T1547.001' 'Starts at every logon and anyone can replace the file.' 'Hash the file and check its creation time.')) } } }
    foreach ($s in $Inv.Startup) { $sv = 'low'; if ($s.FullName -match '(?i)\.(exe|bat|cmd|vbs|js|ps1|hta|scr|jar)$') { $sv = 'medium' }; [void]$f.Add((New-LhFinding $sv 'Persistence' 'File in a Startup folder' "$($s.FullName) (created $($s.CreatedUtc))" 'T1547.001' 'Anything here starts when the user logs on.' 'Open the item and check when it was created.')) }
    foreach ($t in $Inv.Tasks) { $a = [string]$t.Actions; if (-not $a.Trim()) { continue }; $ms = ($t.TaskPath -like '\Microsoft\*')
        $lab = "$($t.TaskPath)$($t.TaskName) as $($t.RunAs): $a"
        $wr = ($a -match $global:LhUserWritable); $lol = ($a -match $susCmd)
        if ($wr -and $t.RunAs -match '(?i)SYSTEM|S-1-5-18') { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'Scheduled task runs a program from a writable folder as SYSTEM' $lab 'T1053.005' 'A task with full rights that runs a file anyone can replace.' 'Check the task creation time (Security 4698) and the file.')) }
        elseif (-not $ms -and ($lol -or $wr)) { [void]$f.Add((New-LhFinding 'medium' 'Persistence' 'Scheduled task that launches a script host or writable-folder file' $lab 'T1053.005' 'Scheduled tasks are a common way to survive reboots.' 'Check who created it and what it runs.')) }
        elseif (-not $ms -and $t.Hidden -and $t.Author -notmatch '(?i)microsoft') { [void]$f.Add((New-LhFinding 'low' 'Persistence' 'Hidden scheduled task' $lab 'T1053.005' 'Hiding a task keeps it out of the normal task list.' 'Check who created it.')) } }
    foreach ($w in $Inv.Wmi) { if ($w.Name -notmatch '^(SCM Event Log (Filter|Consumer)|BVTFilter|TSLogonEvents|TSLogonFilter|RmAssistEventFilter)' -and $w.Class -ne '__FilterToConsumerBinding') { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'WMI event subscription' "$($w.Class) $($w.Name) : $($w.Detail)" 'T1546.003' 'Permanent WMI subscriptions run code without any file on the disk. Very few legitimate programs use them.' 'Read the command or script in the subscription.')) } }
    # registry-based hooks
    $rg = { param($p, $n) try { (Get-ItemProperty -LiteralPath $p -Name $n -ErrorAction Stop).$n } catch { $null } }
    try { $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'; foreach ($k in Get-ChildItem -LiteralPath $ifeo -ErrorAction Stop) { $d = & $rg $k.PSPath 'Debugger'; if ($d) { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'Image File Execution Options debugger set' "$($k.PSChildName) -> $d" 'T1546.012' 'Windows starts the debugger instead of the program. Used to hijack accessibility tools and to persist.' 'Check the debugger program.')) } } } catch {}
    try { foreach ($k in Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit' -ErrorAction Stop) { $m = & $rg $k.PSPath 'MonitorProcess'; if ($m) { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'SilentProcessExit monitor set' "$($k.PSChildName) -> $m" 'T1546.012' 'Runs a program whenever the monitored process exits.' 'Check the monitor program.')) } } } catch {}
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $sh = & $rg $wl 'Shell'; if ($sh -and $sh -notmatch '^(?i)explorer\.exe$') { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'Winlogon Shell was changed' "Shell = $sh" 'T1547.004' 'The Shell should be explorer.exe. Anything else runs at every logon.' 'Check the extra program.')) }
    $ui = & $rg $wl 'Userinit'; if ($ui -and $ui.TrimEnd(',') -notmatch '(?i)^[A-Za-z]:\\Windows\\system32\\userinit\.exe$') { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'Winlogon Userinit was changed' "Userinit = $ui" 'T1547.004' 'Userinit should only be userinit.exe.' 'Check the extra program.')) }
    $aiv = & $rg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' 'AppInit_DLLs'; if ($aiv -and $aiv.Trim()) { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'AppInit_DLLs is set' "AppInit_DLLs = $aiv" 'T1546.010' 'These DLLs are loaded into every program that uses user32.dll.' 'Check each DLL.')) }
    try { $ac = Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCertDlls' -ErrorAction Stop; foreach ($n in $ac.GetValueNames()) { if ($n) { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'AppCertDlls is set' "$n = $($ac.GetValue($n))" 'T1546.009' 'Loaded into every process that creates a process.' 'Check the DLL.')) } } } catch {}
    $be = & $rg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'BootExecute'; if ($be) { $bt = (@($be) -join ' ').Trim(); if ($bt -notmatch '^(?i)autocheck autochk \*$') { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'BootExecute was changed' "BootExecute = $bt" 'T1542' 'Runs before Windows finishes starting.' 'Check the program.')) } }
    $ul = & $rg 'HKCU:\Environment' 'UserInitMprLogonScript'; if ($ul) { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'Logon script set in the user profile' "UserInitMprLogonScript = $ul" 'T1037.001' 'Runs at logon without appearing in the usual autostart lists.' 'Check the script.')) }
    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    foreach ($pair in @(@('Security Packages', $ind.StandardSecurityPackages), @('Authentication Packages', $ind.StandardAuthPackages), @('Notification Packages', $ind.StandardNotificationPackages))) {
        $v = & $rg $lsa $pair[0]; if ($v) { foreach ($e in @($v)) { $e1 = ([string]$e).Trim().Trim('"').ToLower(); if ($e1 -and $pair[1] -notcontains $e1) { [void]$f.Add((New-LhFinding 'medium' 'Persistence' "Unusual LSA $($pair[0])" "$e1 is not on the standard list" 'T1547.002' 'Packages loaded into the security process can capture passwords.' 'Check the DLL and when it was installed.')) } } } }
    try { foreach ($k in Get-ChildItem 'HKCU:\SOFTWARE\Classes\CLSID' -ErrorAction Stop) { $ip = & $rg "$($k.PSPath)\InprocServer32" '(default)'; if (-not $ip) { try { $ip = (Get-ItemProperty -LiteralPath "$($k.PSPath)\InprocServer32" -ErrorAction Stop).'(default)' } catch {} }
        $ipx = [Environment]::ExpandEnvironmentVariables([string]$ip); if ($ip -and $ipx -match $global:LhUserWritable -and (Get-LhSig $ipx).Status -ne 'Valid') { [void]$f.Add((New-LhFinding 'medium' 'Persistence' 'COM object registered in the user profile points to a writable folder' "$($k.PSChildName) -> $ip" 'T1546.015' 'Per-user COM registrations can hijack what a program loads without admin rights.' 'Check the DLL.')) } } } catch {}
    # accessibility programs replaced
    $cmdHash = $null; try { $cmdHash = Get-As4Sha256 "$env:SystemRoot\System32\cmd.exe" } catch {}
    foreach ($n in 'sethc.exe', 'utilman.exe', 'osk.exe', 'narrator.exe', 'magnify.exe', 'displayswitch.exe', 'atbroker.exe') { $p = "$env:SystemRoot\System32\$n"; if (Test-Path -LiteralPath $p) { $h = $null; try { $h = Get-As4Sha256 $p } catch {}; $sg = Get-LhSig $p
        if (($h -and $cmdHash -and $h -eq $cmdHash) -or $sg.Status -in 'HashMismatch', 'NotTrusted') { [void]$f.Add((New-LhFinding 'high' 'Persistence' 'Accessibility program replaced' "$p ($($sg.Status))" 'T1546.008' 'Replacing sethc.exe or utilman.exe with cmd.exe gives a SYSTEM shell from the logon screen.' 'Compare with a clean copy of Windows.')) } } }
    @($f)
}

function Test-LhAccounts {
    param($Inv)
    $f = New-Object Collections.ArrayList
    foreach ($u in $Inv.Users) {
        if ($u.Name -match '\$$') { [void]$f.Add((New-LhFinding 'high' 'Accounts' 'Local account whose name ends with $' "$($u.Name) (enabled: $($u.Enabled))" 'T1136.001' 'A trailing $ hides an account from the net user list.' 'Check when it was created and what it has been used for.')) }
        if ($u.Enabled -and $u.Sid -match '-501$') { [void]$f.Add((New-LhFinding 'medium' 'Accounts' 'Built-in Guest account is enabled' $u.Name 'T1078.001' 'Guest should be off.' 'Check whether it was used (Security 4624).')) }
        elseif ($u.Enabled -and -not $u.PasswordRequired -and $u.Sid -notmatch '-503$') { [void]$f.Add((New-LhFinding 'medium' 'Accounts' 'Enabled account that does not require a password' $u.Name 'T1078.003' 'Anyone with access to the logon screen or RDP may log in.' 'Confirm that this is intended.')) } }
    $names = @($Inv.Admins | ForEach-Object { $_.Name })
    if ($names.Count) { [void]$f.Add((New-LhFinding 'info' 'Accounts' 'Members of the local Administrators group' ($names -join ', ') '' 'Every extra administrator is a possible way back in.' 'Compare with the list the system owner expects.')) }
    if ($names.Count -gt 4) { [void]$f.Add((New-LhFinding 'low' 'Accounts' 'Many local administrators' "$($names.Count) members" 'T1078' 'Larger groups are harder to keep clean.' 'Compare with the list the system owner expects.')) }
    @($f)
}

function Test-LhPosture {
    param($Inv)
    $f = New-Object Collections.ArrayList; $ind = Get-LhIndicators; $p = $Inv.Posture
    if ($p) {
        if ($p.DefenderOff -eq 1 -or $p.DefenderRtOff -eq 1) { [void]$f.Add((New-LhFinding 'high' 'Defences' 'Windows Defender is turned off by policy' "DisableAntiSpyware=$($p.DefenderOff) DisableRealtimeMonitoring=$($p.DefenderRtOff)" 'T1562.001' 'Turning off the antivirus is one of the first things attackers do.' 'Check who set the policy (registry and event log).')) }
        if ($p.WDigest -eq 1) { [void]$f.Add((New-LhFinding 'high' 'Defences' 'WDigest stores passwords in clear text in memory' 'UseLogonCredential = 1' 'T1003.001' 'This setting is not on by default; attackers switch it on so that logons can be read from memory.' 'Collect memory; treat logged-on accounts as exposed.')) }
        if ($p.Uac -eq 0) { [void]$f.Add((New-LhFinding 'medium' 'Defences' 'User Account Control is off' 'EnableLUA = 0' 'T1548.002' 'Programs run with full rights without asking.' 'Check who changed it.')) }
        if ($p.TokenFilter -eq 1) { [void]$f.Add((New-LhFinding 'medium' 'Defences' 'Remote use of local administrator accounts is allowed' 'LocalAccountTokenFilterPolicy = 1' 'T1021.002' 'Makes pass-the-hash style movement with local accounts easy.' 'Check who changed it.')) }
        if ($p.Smb1 -eq 1) { [void]$f.Add((New-LhFinding 'medium' 'Defences' 'SMB version 1 is enabled' 'SMB1 = 1' 'T1210' 'SMBv1 is old and has been used by worms and ransomware.' 'Report to the system owner.')) }
        if ($p.RdpEnabled) { $sv = 'low'; $d = 'Remote Desktop is on'; if ($p.RdpNla -eq 0) { $sv = 'medium'; $d += ' without Network Level Authentication' }; if ($p.RdpPort -and $p.RdpPort -ne 3389) { $sv = 'medium'; $d += "; port changed to $($p.RdpPort)" }
            [void]$f.Add((New-LhFinding $sv 'Defences' 'Remote Desktop is enabled' $d 'T1021.001' 'RDP is the most common way in for ransomware operators. It may be intended here.' 'Check the RDP logons in the event logs.')) }
        if (@($p.PortProxy | Where-Object { $_ }).Count) { [void]$f.Add((New-LhFinding 'high' 'Defences' 'Port forwarding is configured' (@($p.PortProxy) -join '; ') 'T1090' 'netsh portproxy rules forward traffic through this machine, which builds tunnels into a network.' 'Check when it was created and what it points to.')) }
        if ($p.ProxyEnable -eq 1 -or $p.AutoConfigUrl) { [void]$f.Add((New-LhFinding 'low' 'Defences' 'A web proxy is set for the current user' "ProxyServer=$($p.ProxyServer) AutoConfigURL=$($p.AutoConfigUrl)" 'T1090' 'Common in companies; also used to intercept traffic.' 'Confirm it is the company proxy.')) }
        foreach ($d in @($p.Dns)) { if ($d -and -not (Test-LhPrivateIp $d) -and $ind.PublicDns -notcontains $d) { [void]$f.Add((New-LhFinding 'low' 'Defences' 'Unusual public DNS server' $d 'T1584.002' 'A DNS server you do not know can redirect traffic.' 'Confirm it with the network owner.')) } }
        if ($p.ScriptBlockLogging -ne 1) { [void]$f.Add((New-LhFinding 'info' 'Evidence' 'PowerShell script block logging is not forced on' 'EnableScriptBlockLogging is not set by policy' '' 'What PowerShell ran may not be in the event log.' 'Collect PowerShell history and memory instead.')) }
        if ($p.CmdLineAudit -ne 1) { [void]$f.Add((New-LhFinding 'info' 'Evidence' 'Command lines are not recorded in process-creation events' 'ProcessCreationIncludeCmdLine_Enabled is not 1' '' 'Event 4688 will not show what was typed. Look at Sysmon, Prefetch or memory.' 'Rely on memory, Prefetch and PowerShell history.')) }
    }
    $d = $Inv.Defender | Select-Object -First 1
    if ($d -and $d.Available) {
        $other = @($Inv.AntiVirus | Where-Object { $_.Active -and $_.Name -notmatch 'Windows Defender|Microsoft Defender' })
        if (-not $d.RealTime) { if ($other.Count) { [void]$f.Add((New-LhFinding 'info' 'Defences' 'Defender is passive; another antivirus is active' (($other | ForEach-Object { $_.Name }) -join ', ') '' 'Normal when another product protects the machine.' 'Check that product for detections and its own logs.')) }
            else { $avl = (@($Inv.AntiVirus | ForEach-Object { "$($_.Name) ($($_.State))" }) -join ', '); [void]$f.Add((New-LhFinding 'high' 'Defences' 'Real-time antivirus protection is off' "Defender real-time = False. Registered products: $avl" 'T1562.001' 'Nothing is watching files as they are written.' 'Check the Defender log for event 5001 and who turned it off.')) } }
        if ($d.SignatureUpdated -and [datetime]$d.SignatureUpdated -lt (Get-Date).AddDays(-14)) { [void]$f.Add((New-LhFinding 'low' 'Defences' 'Defender signatures are more than 14 days old' $d.SignatureUpdated '' 'Old signatures miss new malware.' 'Informational.')) }
    }
    if ($d) { $ex = @($d.ExclusionPath) + @($d.ExclusionProcess) + @($d.ExclusionExtension) | Where-Object { $_ }
        if ($ex -match 'Must be an administrator') { }
        elseif (@($ex).Count) { $sv = 'medium'; if (@($ex | Where-Object { $_ -match '^[A-Za-z]:\\?$|\\Users\\Public|\\Windows\\Temp|\\ProgramData\\?$|\\AppData\\Local\\Temp|\.(exe|dll|ps1)$' }).Count) { $sv = 'high' }
            [void]$f.Add((New-LhFinding $sv 'Defences' 'Defender exclusions exist' (@($ex) -join '; ') 'T1562.001' 'Anything in an exclusion is never scanned, so attackers add their folders.' 'Compare with what the system owner configured; look for event 5007.')) } }
    foreach ($fw in $Inv.Firewall) { if (-not $fw.Enabled) { [void]$f.Add((New-LhFinding 'medium' 'Defences' "Windows Firewall is off for the $($fw.Name) profile" '' 'T1562.004' 'No host firewall for this network type.' 'Check who turned it off (Firewall log).')) } }
    foreach ($h in $Inv.Hosts) { $sv = 'low'; if ($h.Line -match $ind.HostsSensitive) { $sv = 'medium' }
        if ($h.Line -notmatch '^\s*(127\.0\.0\.1|::1|0\.0\.0\.0)\s+(localhost|.*\.local)\s*$') { [void]$f.Add((New-LhFinding $sv 'Defences' 'Custom entry in the hosts file' $h.Line 'T1565.001' 'The hosts file overrides DNS. Malware uses it to block security sites or redirect traffic.' 'Check the file modification time.')) } }
    @($f)
}

function Test-LhPipes {
    param($Inv)
    $f = New-Object Collections.ArrayList; $ind = Get-LhIndicators
    foreach ($pi in $Inv.Pipes) { foreach ($x in $ind.NamedPipes) { if ($pi.Name -match $x.Pattern) { [void]$f.Add((New-LhFinding $x.Sev 'Tools' $x.Title "Named pipe: $($pi.Name)" 'T1559' 'Some attack tools use fixed pipe names for their internal communication.' 'Capture memory and find the process that owns the pipe.')); break } } }
    @($f)
}

function Test-LhTools {
    # dual-use and attack tools seen in services, installed software, Prefetch and Run keys
    param($Inv)
    $f = New-Object Collections.ArrayList; $ind = Get-LhIndicators; $seen = @{}
    $look = {
        param($text, $where)
        $bn = (([string]$text).ToLower() -replace '\.exe$', '') -replace '[\s-]+', '_'
        foreach ($t in $ind.Tools) { if ($bn -match $t.Pattern) { $k = "$($t.Kind)|$bn"; if (-not $seen.ContainsKey($k)) { $seen[$k] = 1
            [void]$f.Add((New-LhFinding $t.Sev 'Tools' "$($t.Kind): $text" "Seen in $where" $t.Mitre 'The name matches software used by attackers. Some of it is also used by administrators.' 'Decide whether it is authorised here. Find when it was installed or run.')) }; break } } }
    foreach ($s in $Inv.Software) { & $look $s.Name 'installed programs' }
    foreach ($s in $Inv.Services) { & $look $s.Name 'services'; $e = Get-LhExePath $s.PathName; if ($e) { & $look ([IO.Path]::GetFileName($e)) 'services' } }
    $own = Get-As4BundledToolNames
    foreach ($pf in $Inv.Prefetch) { $pb = ([string]$pf.Program).ToLower() -replace '\.exe$', ''; if ($own.Contains($pb) -or $pb -match '^(hayabusa|chainsaw)') { continue }; if ([datetime]$pf.LastWriteUtc -gt (Get-Date).AddDays(-30)) { & $look $pf.Program "Prefetch (ran, last at $($pf.LastWriteUtc))" } }
    foreach ($r in $Inv.RunKeys) { $e = Get-LhExePath $r.Value; if ($e) { & $look ([IO.Path]::GetFileName($e)) 'autostart entries' } }
    @($f)
}

# ---------- event logs (last N days; read-only) ----------
function Get-LhEvents {
    param([string]$Log, [int[]]$Ids, [datetime]$Since, [int]$Max = 2000)
    try { @(Get-WinEvent -FilterHashtable @{ LogName = $Log; Id = $Ids; StartTime = $Since } -MaxEvents $Max -ErrorAction Stop) } catch { @() }
}

function Test-LhEvents {
    param($Inv, [int]$Days = 14)
    $f = New-Object Collections.ArrayList; $since = (Get-Date).AddDays(-$Days); $admin = $Inv.Admin
    # services installed
    $benign = New-Object Collections.ArrayList
    foreach ($e in (Get-LhEvents 'System' @(7045) $since 400)) { $n = [string]$e.Properties[0].Value; $img = [string]$e.Properties[1].Value; $acc = ''; if ($e.Properties.Count -gt 4) { $acc = [string]$e.Properties[4].Value }
        $line = "$($e.TimeCreated.ToString('yyyy-MM-dd HH:mm')) $n : $img ($acc)"
        if ($img -match $global:LhUserWritable -or $img -match '(?i)cmd(\.exe)?\s+/c|powershell|mshta|wscript|cscript|psexesvc|\\\\[A-Za-z0-9.-]+\\') { [void]$f.Add((New-LhFinding 'high' 'Event logs' 'Suspicious service was installed' $line 'T1543.003' 'New services run with high rights and survive reboots. This one runs a script, a temp file or a remote share.' 'Check the file and who logged on at that time.')) }
        else { [void]$benign.Add($line) } }
    if ($benign.Count) { $shown = @($benign | Select-Object -First 12); [void]$f.Add((New-LhFinding 'low' 'Event logs' "Services were installed in the last $Days days" (($shown -join '  ||  ') + $(if ($benign.Count -gt 12) { "  ||  and $($benign.Count - 12) more" } else { '' })) 'T1543.003' 'Updates and new software install services; so do attackers. Look for ones you do not recognise.' 'Compare the list with what was installed or updated.')) }
    # logs cleared
    foreach ($e in (Get-LhEvents 'System' @(104) (Get-Date).AddDays(-90) 20)) { [void]$f.Add((New-LhFinding 'high' 'Event logs' 'An event log was cleared' "System log event 104 at $($e.TimeCreated.ToString('yyyy-MM-dd HH:mm'))" 'T1070.001' 'Clearing logs removes evidence of earlier activity.' 'Work out what was in the cleared log from other sources (memory, Prefetch, backups).')) }
    # Defender
    $dev = Get-LhEvents 'Microsoft-Windows-Windows Defender/Operational' @(1116, 1117, 5001) $since 300
    $threats = @{}; foreach ($e in $dev | Where-Object { $_.Id -in 1116, 1117 }) { if (Test-As4SelfText $e.Message) { continue }; if ($e.Message -match '(?m)^\s*(Name|Threat Name)\s*:\s*(.+)$') { $threats[$Matches[2].Trim()] = $e.TimeCreated } }
    foreach ($k in $threats.Keys) { [void]$f.Add((New-LhFinding 'high' 'Event logs' 'Windows Defender reported a threat' "$k (last at $($threats[$k].ToString('yyyy-MM-dd HH:mm')))" 'T1204' 'Defender found something. Check whether it was cleaned and whether it ran first.' 'Look at the Defender history and the path it reports.')) }
    if (@($dev | Where-Object Id -eq 5001).Count) { [void]$f.Add((New-LhFinding 'high' 'Event logs' 'Defender real-time protection was switched off' "Event 5001, last at $((@($dev | Where-Object Id -eq 5001)[0]).TimeCreated.ToString('yyyy-MM-dd HH:mm'))" 'T1562.001' 'Protection was turned off at some point.' 'Find who did it and what happened after.')) }
    # RDP accepted
    $rdp = @(Get-LhEvents 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' @(1149) $since 600)
    $ips = @{}; foreach ($e in $rdp) { $ip = ''; if ($e.Properties.Count -gt 2) { $ip = [string]$e.Properties[2].Value }; if ($ip) { if (-not $ips.ContainsKey($ip)) { $ips[$ip] = 0 }; $ips[$ip]++ } }
    foreach ($ip in $ips.Keys) { $ext = -not (Test-LhPrivateIp $ip); $sv = 'info'; if ($ext) { $sv = 'medium' }; [void]$f.Add((New-LhFinding $sv 'Event logs' $(if ($ext) { 'Remote Desktop login accepted from an internet address' } else { 'Remote Desktop login accepted from the local network' }) "$ip : $($ips[$ip]) time(s) in $Days days" 'T1021.001' 'RDP from an address you do not know is a common first step of an intrusion.' 'Check the account used and what ran afterwards.')) }
    # PowerShell script blocks
    $psb = @(Get-LhEvents 'Microsoft-Windows-PowerShell/Operational' @(4104) $since 800 | Where-Object { $_.Message -notmatch 'Get-LhIndicators|New-LhFinding|Test-Lh|Invoke-LiveHunt|AS4 IR Tool|Invoke-As4' })
    $hitA = @($psb | Where-Object { $_.Message -match '(?i)amsiutils|amsiInitFailed|AmsiScanBuffer' }); $hitB = @($psb | Where-Object { $_.Message -match '(?i)FromBase64String|DownloadString|Invoke-Mimikatz|System\.Net\.WebClient|Reflection\.Assembly\]::Load|VirtualAlloc' })
    if ($hitA.Count) { [void]$f.Add((New-LhFinding 'high' 'Event logs' 'PowerShell script tried to disable AMSI' "$($hitA.Count) script block(s), latest $($hitA[0].TimeCreated.ToString('yyyy-MM-dd HH:mm'))" 'T1562.001' 'AMSI is how Windows lets antivirus look into scripts. Bypass code is not in normal scripts.' 'Read the script block text in the PowerShell log.')) }
    if ($hitB.Count) { [void]$f.Add((New-LhFinding 'medium' 'Event logs' 'PowerShell scripts with download, decode or in-memory loading' "$($hitB.Count) script block(s), latest $($hitB[0].TimeCreated.ToString('yyyy-MM-dd HH:mm'))" 'T1059.001' 'These calls are used by loaders, but also by some admin scripts.' 'Read the script block text.')) }
    # Security log (administrator only)
    if ($admin) {
        foreach ($e in (Get-LhEvents 'Security' @(1102) (Get-Date).AddDays(-90) 20)) { [void]$f.Add((New-LhFinding 'high' 'Event logs' 'The Security event log was cleared' "Event 1102 at $($e.TimeCreated.ToString('yyyy-MM-dd HH:mm'))" 'T1070.001' 'Clearing logs removes evidence of earlier activity.' 'Reconstruct from other sources.')) }
        $fail = Get-LhEvents 'Security' @(4625) $since 1500
        $byIp = @{}; foreach ($e in $fail) { $ip = [string]$e.Properties[19].Value; if ($ip -and $ip -ne '-') { if (-not $byIp.ContainsKey($ip)) { $byIp[$ip] = 0 }; $byIp[$ip]++ } }
        $hot = @{}; foreach ($ip in $byIp.Keys) { if ($byIp[$ip] -ge 20) { $hot[$ip] = $byIp[$ip]; $sv = 'medium'; if ($byIp[$ip] -ge 100) { $sv = 'high' }; [void]$f.Add((New-LhFinding $sv 'Event logs' 'Many failed logons from one address' "$ip : $($byIp[$ip]) failures in $Days days" 'T1110' 'Repeated failures from one source look like password guessing.' 'Check for a successful logon from the same address.')) } }
        if ($hot.Count) { foreach ($e in (Get-LhEvents 'Security' @(4624) $since 1500)) { $lt = [int]$e.Properties[8].Value; $ip = [string]$e.Properties[18].Value; if ($lt -in 3, 10 -and $hot.ContainsKey($ip)) { [void]$f.Add((New-LhFinding 'high' 'Event logs' 'Successful logon from an address that had many failures' "$ip logged on as $($e.Properties[5].Value) (type $lt) at $($e.TimeCreated.ToString('yyyy-MM-dd HH:mm'))" 'T1110' 'Guessing followed by success means the guess may have worked.' 'Treat the account as exposed; review what it did.')); break } } }
        foreach ($e in (Get-LhEvents 'Security' @(4720, 4728, 4732, 4756) $since 300)) { $t = switch ($e.Id) { 4720 { 'User account was created' } default { 'Member was added to a privileged group' } }; $d = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm'); $x = if ($e.Id -eq 4720) { "$($e.Properties[0].Value) created by $($e.Properties[4].Value) at $d" } else { "$($e.Properties[0].Value) added to $($e.Properties[2].Value) by $($e.Properties[6].Value) at $d" }
            [void]$f.Add((New-LhFinding 'medium' 'Event logs' $t $x 'T1136.001' 'New accounts and new administrators are a way back in.' 'Confirm that the change was approved.')) }
    }
    @($f)
}

# ---------- recently dropped files (time boxed) ----------
function Get-LhRecentFiles {
    param([string[]]$Roots, [datetime]$Since, [string[]]$Ext, [int]$BudgetSec = 15, [int]$Cap = 300)
    $sw = [Diagnostics.Stopwatch]::StartNew(); $out = New-Object Collections.ArrayList; $stack = New-Object Collections.Stack
    foreach ($r in $Roots) { if (Test-Path -LiteralPath $r -ErrorAction SilentlyContinue) { $stack.Push($r) } }
    while ($stack.Count -and $sw.Elapsed.TotalSeconds -lt $BudgetSec -and $out.Count -lt $Cap) {
        $d = [string]$stack.Pop()
        try { $di = New-Object IO.DirectoryInfo($d); if (($di.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $d -ne $di.FullName) { continue }
            foreach ($file in $di.EnumerateFiles()) { if ($Ext -contains $file.Extension.ToLower() -and $file.CreationTime -gt $Since) { [void]$out.Add($file); if ($out.Count -ge $Cap) { break } } }
            foreach ($sub in $di.EnumerateDirectories()) { if (-not ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($sub.FullName) } }
        } catch {}
        Invoke-LhPause 3
        if ($global:Cancel) { break }
    }
    , @($out)
}

function Test-LhFiles {
    param([int]$Days = 3, [int]$BudgetSec = 15)
    $f = New-Object Collections.ArrayList; $since = (Get-Date).AddDays(-$Days)
    $roots = @("$env:SystemRoot\Temp", "$env:PUBLIC", "$env:ProgramData"); Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $roots += "$($_.FullName)\Downloads", "$($_.FullName)\Desktop", "$($_.FullName)\AppData\Local\Temp", "$($_.FullName)\AppData\Roaming" }
    $files = Get-LhRecentFiles -Roots $roots -Since $since -Ext @('.exe', '.dll', '.scr', '.ps1', '.bat', '.cmd', '.vbs', '.js', '.hta', '.jar') -BudgetSec $BudgetSec -Cap 400
    $scripts = @(); $checked = 0
    foreach ($x in $files) {
        if ($x.FullName.StartsWith($global:P.Root + '\', [StringComparison]::OrdinalIgnoreCase) -or $x.FullName.StartsWith($global:P.Output + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($x.Extension -in '.exe', '.dll', '.scr') { if ($checked -ge 80) { continue }; $checked++; $sg = Get-LhSig $x.FullName
            if ($sg.Status -ne 'Valid') { $sv = 'medium'; if ($x.FullName -match $global:LhHighRisk -and $x.Extension -eq '.exe') { $sv = 'high' }; [void]$f.Add((New-LhFinding $sv 'Files' 'Unsigned program or library created in the last few days in a writable folder' "$($x.FullName) ($($x.Length) bytes, created $($x.CreationTime.ToString('yyyy-MM-dd HH:mm')))" 'T1105' 'Dropped payloads often land in these folders.' 'Hash the file and check it on your intelligence source.')) } }
        else { $scripts += $x } }
    if ($scripts.Count) { $shown = @($scripts | Select-Object -First 10 | ForEach-Object { "$($_.FullName) ($($_.CreationTime.ToString('yyyy-MM-dd HH:mm')))" }); [void]$f.Add((New-LhFinding 'low' 'Files' "Script files were created in the last $Days days in writable folders" (($shown -join '  ||  ') + $(if ($scripts.Count -gt 10) { "  ||  and $($scripts.Count - 10) more" } else { '' })) 'T1059' 'Scripts in these folders may be installers, or droppers.' 'Read the ones you do not recognise.')) }
    @($f)
}

# ---------- verdict ----------
function Get-LhVerdict {
    param($Findings)
    $pts = @{ high = 25; medium = 8; low = 2; info = 0 }; $score = 0; $reasons = @()
    foreach ($g in ($Findings | Where-Object { $_.Sev -ne 'info' } | Group-Object Title)) { $base = $pts[$g.Group[0].Sev]; $p = $base + [Math]::Min(10, ($g.Count - 1) * [Math]::Max(1, [int]($base / 5))); $score += $p; $reasons += [pscustomobject]@{ Points = $p; Text = "$($g.Name)$(if ($g.Count -gt 1) { " ($($g.Count) times)" })"; Sev = $g.Group[0].Sev } }
    $high = @($Findings | Where-Object Sev -eq 'high').Count
    $v = 'Nothing stood out'; $c = 'green'; $t = 'None of the checks found something unusual. This does not prove the machine is clean; it only means these checks found nothing.'
    if ($score -ge 1) { $v = 'A few things to review'; $c = 'yellow'; $t = 'Some items are unusual but have common harmless explanations. Look at them and decide.' }
    if ($score -ge 15 -or $high -ge 1) { $v = 'Worth a closer look'; $c = 'orange'; $t = 'At least one item is a strong lead. Look at it before doing anything else on this machine.' }
    if ($score -ge 50) { $v = 'Strong leads'; $c = 'red'; $t = 'Several independent checks found things that attackers do. Treat this machine as suspicious until reviewed.' }
    if ($score -ge 100) { $v = 'Many strong leads'; $c = 'darkred'; $t = 'There are many signs from different areas. Consider isolating the machine according to your procedure and capture memory first.' }
    [pscustomobject]@{ Verdict = $v; Color = $c; Text = $t; Score = $score; High = $high; Reasons = @($reasons | Sort-Object Points -Descending) }
}

function Get-LhNextSteps {
    param($Findings, $Verdict)
    $n = New-Object Collections.ArrayList
    if ($Verdict.High -ge 1) { [void]$n.Add('Capture memory first (Memory page): running processes, keys and network state are lost when the machine is switched off or restarted.') }
    foreach ($x in ($Findings | Where-Object { $_.Sev -eq 'high' -and $_.Next } | Group-Object Next | Sort-Object Count -Descending | Select-Object -First 5)) { [void]$n.Add($x.Name) }
    if ($Verdict.Score -ge 8) { [void]$n.Add('Run First Response > Suspected malware to copy the files and logs that prove or disprove these leads.'); [void]$n.Add('Export the event logs and run Quick Scan on them.') }
    if ($Verdict.Score -eq 0) { [void]$n.Add('If this machine was flagged by something else, collect its event logs and run Quick Scan; the live state alone cannot show what happened earlier.') }
    [void]$n.Add('Write down the time you started, who has access and what you changed (Evidence package > notes).')
    @($n)
}

function Get-LhBlindSpots {
    param($Inv)
    $b = New-Object Collections.ArrayList
    if (-not $Inv.Admin) { foreach ($t in 'The Security log (logons, account changes) was not read - administrator is needed.', 'Paths and command lines of other users'' and system processes may be hidden.', 'Defender exclusions and Prefetch were not read.') { [void]$b.Add($t) } }
    foreach ($e in $Inv.Errors) { [void]$b.Add("Could not read: $e") }
    foreach ($t in 'This is a view of one moment. Programs that have already exited are not visible; the event logs and Prefetch cover some of that.', 'Code that only lives in memory, or that hides itself from Windows (rootkits), can be invisible to live checks. Memory capture covers that.', 'Rules are heuristics. Each item is a lead for a person to confirm.') { [void]$b.Add($t) }
    @($b)
}
