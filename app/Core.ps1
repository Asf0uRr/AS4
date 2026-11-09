# AS4 IR Tool - core engine. ASCII only (PowerShell 5.1 safe). Dot-source this file.
# No network access, no installs, no remediation. Every action is logged and manifested.

$global:AS4Version = '1.1.0'
$global:AS4Name    = 'AS4 IR Tool'
$global:P          = $null     # path table
$global:Case       = $null     # active case
$global:RunId      = $null
$global:Cancel     = $false    # cooperative cancellation flag
$global:UiLog      = $null     # optional scriptblock($level,$msg)
$global:UiPump     = $null     # optional scriptblock called while waiting (keeps GUI alive)
$global:Utf8       = New-Object System.Text.UTF8Encoding($false)
$global:As4Priority = 'BelowNormal'   # tools run at low priority so the endpoint stays usable

$global:CaseFolders = [ordered]@{
    Meta='00_Metadata'; Sys='01_System_Info'; Net='02_Network'; Proc='03_Processes_Services'
    Auth='04_Users_Authentication'; Evtx='05_Event_Logs'; Kape='06_KAPE'; Mem='07_Memory'
    Disk='08_Disk'; Persist='09_Persistence'; Art='10_Artifacts'; Chain='11_Chainsaw_Analysis'; Hay='11_Hayabusa_Analysis'
    Rep='12_Reports'; Logs='13_Collection_Logs'; Live='14_Live_Analysis'
}


# ---------- brand mark: a small pixel bird (X = body, e = eye) ----------
$global:BirdRows = @(
    '.........XXXXXX.......',
    '.......XXXXXXXXXX.....',
    '......XXXXXXXXXeXXXXXX',
    '..X..XXXXXXXXXXXXX....',
    '.XXXXXXXXXXXXXXXXX....',
    'XXXXXXXXXXXXXXXXX.....',
    '.XXXXXXXXXXXXXXXX.....',
    '...XXXXXXXXXXXXX......',
    '.....XXXXXXXXXX.......',
    '......XX...XX.........',
    '......XX...XX.........'
)
function Get-As4BirdSvg {
    param([int]$Height = 28, [string]$Fill = '#3ddc84')
    $rows = $global:BirdRows; $w = ($rows | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum; $r = New-Object Text.StringBuilder
    for ($y = 0; $y -lt $rows.Count; $y++) { for ($x = 0; $x -lt $rows[$y].Length; $x++) { $c = $rows[$y][$x]; if ($c -eq 'X') { [void]$r.Append("<rect x='$x' y='$y' width='1' height='1'/>") } elseif ($c -eq 'e') { [void]$r.Append("<rect x='$x' y='$y' width='1' height='1' fill='#0b1110'/>") } } }
    $wd = [int]($Height * $w / $rows.Count)
    "<svg xmlns='http://www.w3.org/2000/svg' width='$wd' height='$Height' viewBox='0 0 $w $($rows.Count)' fill='$Fill' shape-rendering='crispEdges' style='vertical-align:middle'>$($r.ToString())</svg>"
}

# ---------- AS4's own footprint: left out of findings so scans describe the machine, not this tool ----------
$global:SelfRx = $null
function Get-As4SelfConfig {
    $f = Join-Path $global:P.Profiles 'self_exclusions.json'
    if (Test-Path -LiteralPath $f) { try { return (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) } catch {} }
    [pscustomobject]@{ Markers = @('AS4 IR Tool'); BundledToolNames = @(); Extra = @() }
}
function Get-As4SelfRegex {
    if ($global:SelfRx) { return $global:SelfRx }
    $p = New-Object Collections.ArrayList; $cfg = Get-As4SelfConfig
    foreach ($d in @($global:P.Root, $global:P.Output)) { if ($d) { [void]$p.Add([regex]::Escape($d)); [void]$p.Add([regex]::Escape($d.Replace([string][char]92, '/'))); [void]$p.Add([regex]::Escape($d.Replace([string][char]92, ([string][char]92 + [char]92)))) } }
    foreach ($m in @($cfg.Markers) + @($cfg.Extra)) { if ($m) { [void]$p.Add([string]$m) } }
    $global:SelfRx = New-Object Text.RegularExpressions.Regex(('(' + ($p -join '|') + ')'), 'IgnoreCase')
    $global:SelfRx
}
function Test-As4SelfText { param([string]$Text) if (-not $Text) { return $false }; (Get-As4SelfRegex).IsMatch($Text) }
function Get-As4BundledToolNames {
    # lower-case file names (without .exe) of the programs in tools\, plus the configured list: used to ignore AS4 running its own tools
    $n = New-Object Collections.Generic.HashSet[string]; $cfg = Get-As4SelfConfig
    foreach ($x in @($cfg.BundledToolNames)) { [void]$n.Add(([string]$x).ToLower()) }
    try { foreach ($t in (Get-As4Tools)) { if ($t.Path) { [void]$n.Add(([IO.Path]::GetFileNameWithoutExtension($t.Path)).ToLower()) } } } catch {}
    , $n
}

function Initialize-As4 {
    param([Parameter(Mandatory)][string]$Root)
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $global:SelfRx = $null
    $global:P = @{
        Root=$r; App="$r\app"; Tasks="$r\tasks"; Tools="$r\tools"; Config="$r\config"; Profiles="$r\config\profiles"; Rules="$r\config\rules"
        Scripts="$r\scripts"; Docs="$r\docs"; Output="$r\output"
    }
    if (-not (Test-Path -LiteralPath $global:P.Output)) { New-Item -ItemType Directory -Path $global:P.Output -Force | Out-Null }
    $rtDir = Join-Path $r 'tools\_runtime\x64'; if ((Test-Path -LiteralPath $rtDir) -and ($env:PATH -notlike "*$rtDir*")) { $env:PATH = $env:PATH + ';' + $rtDir }   # last-resort DLL search for tools started from this process
}

function Get-UtcNow { (Get-Date).ToUniversalTime() }
function Get-UtcStamp { (Get-UtcNow).ToString('yyyyMMddTHHmmssfffZ') }
function Get-UtcIso { param($d) if (-not $d) { $d = Get-UtcNow }; ([datetime]$d).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }

function Write-As4Log {
    param([string]$Level = 'INFO', [string]$Msg)
    $line = '{0} [{1}] {2}' -f (Get-UtcIso), $Level, $Msg
    try {
        if ($global:P) { [IO.File]::AppendAllText("$($global:P.Logs)\as4_$((Get-UtcNow).ToString('yyyyMMdd')).log", $line + "`r`n", $global:Utf8) }
        if ($global:Case) { [IO.File]::AppendAllText("$($global:Case.Dir)\$($global:CaseFolders.Logs)\session.log", $line + "`r`n", $global:Utf8) }
    } catch {}
    if ($global:UiLog) { & $global:UiLog $Level $Msg }
    else {
        $c = switch ($Level) { 'ERROR' {'Red'} 'WARN' {'Yellow'} 'OK' {'Green'} default {'Gray'} }
        Write-Host $line -ForegroundColor $c
    }
}

function Test-As4Admin {
    try { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $false }
}

function Get-As4Host {
    $os = $null; try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch {}
    $drive = [IO.Path]::GetPathRoot($global:P.Root)
    $free = $null; try { $free = [math]::Round((New-Object IO.DriveInfo($drive)).AvailableFreeSpace / 1GB, 1) } catch {}
    [pscustomobject]@{
        Computer = $env:COMPUTERNAME; User = "$env:USERDOMAIN\$env:USERNAME"
        OS = if ($os) { "$($os.Caption) build $($os.BuildNumber)" } else { [Environment]::OSVersion.VersionString }
        Arch = $env:PROCESSOR_ARCHITECTURE; PowerShell = $PSVersionTable.PSVersion.ToString()
        Admin = (Test-As4Admin); Root = $global:P.Root; DriveFreeGB = $free
    }
}

# ---------- hashing / files ----------
function Get-As4Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    $fs = $null; $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete), 1048576)
        ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally { if ($fs) { $fs.Dispose() }; $sha.Dispose() }
}

function Get-UniquePath {
    param([string]$Dir, [string]$Base, [string]$Ext)
    if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $safe = ($Base -replace '[^A-Za-z0-9._-]', '_')
    $p = Join-Path $Dir ("{0}_{1}.{2}" -f $safe, (Get-UtcStamp), $Ext.TrimStart('.'))
    $i = 1; while (Test-Path -LiteralPath $p) { $p = Join-Path $Dir ("{0}_{1}_{2}.{3}" -f $safe, (Get-UtcStamp), $i, $Ext.TrimStart('.')); $i++ }
    $p
}

function Write-As4File {
    # never overwrites: refuses if the file exists
    param([string]$Path, [string]$Text)
    if (Test-Path -LiteralPath $Path) { throw "Refusing to overwrite existing evidence file: $Path" }
    $d = Split-Path $Path; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $global:Utf8)
}

function Get-RelPath { param([string]$Full) $b = $global:Case.Dir.TrimEnd('\') + '\'; if ($Full.StartsWith($b, [StringComparison]::OrdinalIgnoreCase)) { $Full.Substring($b.Length) } else { $Full } }

function Register-As4Files {
    # hash files and append to case hashes.csv (evidence hash ledger)
    param([string[]]$Files, [string]$Kind = 'raw')
    $out = @()
    foreach ($f in $Files) {
        if (-not $f -or -not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        $h = $null; $err = $null
        try { $h = Get-As4Sha256 $f } catch { $err = $_.Exception.Message; Write-As4Log WARN "Hash failed for ${f}: $err" }
        $fi = Get-Item -LiteralPath $f
        $row = [pscustomobject]@{ Sha256 = $h; Size = $fi.Length; RelativePath = (Get-RelPath $f); Kind = $Kind; RunId = $global:RunId; HashedUtc = Get-UtcIso; Error = $err }
        $out += $row
    }
    if ($out.Count) {
        $led = "$($global:Case.Dir)\$($global:CaseFolders.Meta)\hashes.csv"
        $csv = $out | ConvertTo-Csv -NoTypeInformation
        if (Test-Path -LiteralPath $led) { $csv = $csv | Select-Object -Skip 1 }
        [IO.File]::AppendAllText($led, (($csv -join "`r`n") + "`r`n"), $global:Utf8)
    }
    $out
}

function Test-As4Hashes {
    param([string]$CaseDir)
    $led = Join-Path $CaseDir '00_Metadata\hashes.csv'
    if (-not (Test-Path -LiteralPath $led)) { throw "No hash ledger at $led" }
    $res = @()
    foreach ($r in (Import-Csv -LiteralPath $led)) {
        $p = if ([IO.Path]::IsPathRooted($r.RelativePath)) { $r.RelativePath } else { Join-Path $CaseDir $r.RelativePath }; $st = 'OK'; $now = $null
        if (-not (Test-Path -LiteralPath $p)) { $st = 'MISSING' }
        elseif (-not $r.Sha256) { $st = 'NO_ORIGINAL_HASH' }
        else { try { $now = Get-As4Sha256 $p; if ($now -ne $r.Sha256) { $st = 'MISMATCH' } } catch { $st = 'HASH_ERROR' } }
        $res += [pscustomobject]@{ Status = $st; RelativePath = $r.RelativePath; Expected = $r.Sha256; Actual = $now }
    }
    $res
}

# ---------- cases ----------
function Test-As4CaseName {
    param([string]$Name)
    $n = if ($Name) { $Name.Trim() } else { '' }
    if (-not $n) { throw 'Enter a case name.' }
    if ($n.Length -gt 80) { throw 'Case name is too long (80 characters maximum).' }
    if ($n -match '[\x5c/:*?"<>|\x00-\x1f]') { throw 'Case name cannot contain \ / : * ? " < > | or control characters.' }
    if ($n -match '^\.+$' -or $n -match '[. ]$') { throw 'Case name cannot be only dots or end with a dot or space.' }
    if ($n -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') { throw 'That name is reserved by Windows.' }
    $n
}

function Start-As4Case {
    # Creates output\<name>\ or resumes it. Nothing already in the folder is ever overwritten.
    param([Parameter(Mandatory)][string]$Name)
    $n = Test-As4CaseName $Name
    $dir = Join-Path $global:P.Output $n
    $mf = Join-Path $dir '00_Metadata\case.json'
    if (Test-Path -LiteralPath $dir) {
        if (-not (Test-Path -LiteralPath $mf)) { throw "A folder named '$n' already exists in output\ but is not an AS4 case. Choose another name." }
        $meta = Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json
        $global:Case = @{ Id = $n; Dir = $dir; Meta = $meta; Resumed = $true }
        New-Item -ItemType Directory -Path (Join-Path $dir $global:CaseFolders.Logs) -Force | Out-Null
        Write-As4Log INFO "Case resumed: $n"
        return $global:Case
    }
    foreach ($f in $global:CaseFolders.Meta, $global:CaseFolders.Logs) { New-Item -ItemType Directory -Path (Join-Path $dir $f) -Force | Out-Null }
    $meta = [ordered]@{ CaseName = $n; CreatedUtc = Get-UtcIso; Analyst = $env:USERNAME; AnalystWorkstation = $env:COMPUTERNAME; ToolVersion = $global:AS4Version }
    Write-As4File $mf ($meta | ConvertTo-Json)
    $global:Case = @{ Id = $n; Dir = $dir; Meta = $meta; Resumed = $false }
    Write-As4Log OK "Case created: $n -> $dir"
    $global:Case
}

function Get-As4Cases {
    if (-not (Test-Path -LiteralPath $global:P.Output)) { return @() }
    Get-ChildItem -LiteralPath $global:P.Output -Directory | Where-Object { Test-Path (Join-Path $_.FullName '00_Metadata\case.json') } | Sort-Object LastWriteTime -Descending | ForEach-Object { $_.Name }
}

function Get-CaseFolder {
    param([string]$Key)
    if (-not $global:Case) { throw 'No active case. Create or open a case first.' }
    $d = Join-Path $global:Case.Dir $global:CaseFolders[$Key]
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $d
}

function Start-As4Run {
    param([string]$Label = 'run')
    if (-not $global:Case) { throw 'No active case.' }
    $global:Cancel = $false
    $global:RunId = 'RUN-' + (Get-UtcStamp)
    Write-As4Log INFO "Run started: $($global:RunId) ($Label) admin=$(Test-As4Admin)"
    $global:RunId
}

function Stop-As4Run {
    # seal: hash manifest + ledger so later tampering is detectable
    $m = Get-CaseFolder 'Meta'
    $logs = Get-CaseFolder 'Logs'
    $lines = @()
    foreach ($f in "$logs\manifest.jsonl", "$m\hashes.csv", "$m\case.json") {
        if (Test-Path -LiteralPath $f) { $lines += ('{0}  {1}' -f (Get-As4Sha256 $f), (Get-RelPath $f)) }
    }
    $seal = Join-Path $m ("seal_{0}.sha256" -f $global:RunId)
    if ($lines.Count -and -not (Test-Path -LiteralPath $seal)) { Write-As4File $seal (($lines -join "`r`n") + "`r`n") }
    Write-As4Log INFO "Run ended: $($global:RunId)"
}

# ---------- manifest ----------
function Add-As4Manifest {
    param([hashtable]$Entry)
    $logs = Get-CaseFolder 'Logs'
    $Entry['RunId'] = $global:RunId
    $json = ($Entry | ConvertTo-Json -Compress -Depth 5)
    [IO.File]::AppendAllText("$logs\manifest.jsonl", $json + "`r`n", $global:Utf8)
}

function Get-As4Manifest {
    param([string]$CaseDir)
    $f = Join-Path $CaseDir '13_Collection_Logs\manifest.jsonl'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    Get-Content -LiteralPath $f -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
}

function Get-As4Summary {
    param([string]$CaseDir, [string]$RunId)
    $m = Get-As4Manifest $CaseDir
    if ($RunId) { $m = $m | Where-Object { $_.RunId -eq $RunId } }
    $g = $m | Group-Object Status
    $o = [ordered]@{ Total = @($m).Count }
    foreach ($x in $g) { $o[$x.Name] = $x.Count }
    [pscustomobject]$o
}

# ---------- native process runner ----------
function ConvertTo-ArgString {
    param([string[]]$ArgList)
    ($ArgList | ForEach-Object {
        $s = [string]$_
        if ($s -eq '') { '""' }
        elseif ($s -notmatch '[\s"]') { $s }
        else { '"' + (($s -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
    }) -join ' '
}

function Resolve-As4Exe {
    param([string]$Exe)
    if ([IO.Path]::IsPathRooted($Exe)) { if (Test-Path -LiteralPath $Exe -PathType Leaf) { return $Exe } else { return $null } }
    $sys = Join-Path $env:SystemRoot "System32\$Exe"
    if (Test-Path -LiteralPath $sys -PathType Leaf) { return $sys }
    $c = Get-Command $Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    $null
}

function Invoke-As4Native {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @(), [int]$TimeoutSec = 120, [string]$WorkDir)
    $res = [ordered]@{ Exe = $Exe; ArgString = ''; ExitCode = $null; StdOut = ''; StdErr = ''; TimedOut = $false; Cancelled = $false; StartUtc = Get-UtcIso; EndUtc = $null; Error = $null }
    $path = Resolve-As4Exe $Exe
    if (-not $path) { $res.Error = "Command not found: $Exe"; $res.EndUtc = Get-UtcIso; return [pscustomobject]$res }
    $res.Exe = $path
    $tdir = Split-Path $path; if ($global:P -and $tdir.StartsWith($global:P.Tools, [StringComparison]::OrdinalIgnoreCase) -and -not $global:RtChecked.ContainsKey($tdir)) { $global:RtChecked[$tdir] = 1; foreach ($x in @(Repair-As4ToolRuntimes -Folders @($tdir))) { Write-As4Log $(if ($x.Ok) { 'INFO' } else { 'WARN' }) "Runtime library $($x.Dll) for $($x.Needed): $($x.Action)" } }
    $res.ArgString = ConvertTo-ArgString $Arguments
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $path; $psi.Arguments = $res.ArgString
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    try { $oem = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage); $psi.StandardOutputEncoding = $oem; $psi.StandardErrorEncoding = $oem } catch {}
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    $p = New-Object Diagnostics.Process; $p.StartInfo = $psi
    try {
        [void]$p.Start()
        try { if ($global:As4Priority) { $p.PriorityClass = $global:As4Priority } } catch {}
        $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.WaitForExit(150)) {
            if ($global:UiPump) { & $global:UiPump }
            if ($global:Cancel) { $res.Cancelled = $true; try { $p.Kill() } catch {}; break }
            if ($TimeoutSec -gt 0 -and $sw.Elapsed.TotalSeconds -gt $TimeoutSec) { $res.TimedOut = $true; try { $p.Kill() } catch {}; break }
        }
        try { $p.WaitForExit(3000) | Out-Null } catch {}
        try { $res.StdOut = $so.Result; $res.StdErr = $se.Result } catch {}
        if ($p.HasExited) { $res.ExitCode = $p.ExitCode }
    } catch { $res.Error = $_.Exception.Message }
    finally { $p.Dispose() }
    $res.EndUtc = Get-UtcIso
    [pscustomobject]$res
}

# ---------- task engine ----------
# Task: Id, Name, Folder(key), Type(native|ps), Exe, Args, Script, Admin(none|partial|required), Ext, Timeout,
#       Desc, Why, Sensitive, Live, Quick, Full
function New-As4Task {
    param([hashtable]$H)
    $d = @{ Type='native'; Admin='none'; Ext='txt'; Timeout=120; Sensitive=$false; Live=$true; Quick=$false; Full=$true; Args=@(); Why=''; Desc='' }
    foreach ($k in $H.Keys) { $d[$k] = $H[$k] }
    [pscustomobject]$d
}

function Invoke-As4Task {
    param([Parameter(Mandatory)]$Task)
    $started = Get-UtcNow
    $entry = [ordered]@{ TaskId = $Task.Id; Name = $Task.Name; Category = $Task.Folder; Status = 'FAILED'; StartUtc = Get-UtcIso $started; EndUtc = $null
        ExitCode = $null; Command = $null; Arguments = $null; ToolVersion = $null; Source = 'live system'; Destination = @(); Sha256 = @(); Notes = @(); Warnings = @() }
    $outFiles = @()
    Write-As4Log INFO "BEGIN $($Task.Id) - $($Task.Name)"
    try {
        if ($global:Cancel) { $entry.Status = 'CANCELLED'; throw [OperationCanceledException]::new('cancelled before start') }
        $isAdmin = Test-As4Admin
        if ($Task.Admin -eq 'required' -and -not $isAdmin) {
            $entry.Status = 'SKIPPED'; $entry.Notes += 'Requires administrator privileges; not running elevated.'
            Write-As4Log WARN "$($Task.Id) skipped: requires administrator"
        } else {
            if ($Task.Admin -eq 'partial' -and -not $isAdmin) { $entry.Warnings += 'Not elevated: results may be incomplete (e.g. other users'' processes).'; Write-As4Log WARN "$($Task.Id): not elevated, output may be incomplete" }
            $dir = Get-CaseFolder $Task.Folder
            if ($Task.Type -eq 'native') {
                $r = Invoke-As4Native -Exe $Task.Exe -Arguments $Task.Args -TimeoutSec $Task.Timeout
                $entry.Command = $r.Exe; $entry.Arguments = $r.ArgString; $entry.ExitCode = $r.ExitCode
                $entry.StartUtc = $r.StartUtc; $entry.EndUtc = $r.EndUtc
                if ($r.Error) { $entry.Status = 'SKIPPED'; $entry.Notes += $r.Error }
                else {
                    $f = Get-UniquePath $dir $Task.Id $Task.Ext
                    $hdr = "# AS4 IR Tool | task=$($Task.Id) | run=$($global:RunId) | startUtc=$($r.StartUtc) | cmd=$($r.Exe) $($r.ArgString) | exit=$($r.ExitCode)`r`n"
                    $body = $r.StdOut
                    if ($Task.Ext -in 'csv','json') { $hdr = '' }
                    Write-As4File $f ($hdr + $body); $outFiles += $f
                    if ($r.StdErr.Trim()) { $ef = Get-UniquePath $dir ($Task.Id + '_stderr') 'txt'; Write-As4File $ef $r.StdErr; $outFiles += $ef; $entry.Warnings += 'stderr output captured' }
                    if ($r.Cancelled) { $entry.Status = 'CANCELLED' }
                    elseif ($r.TimedOut) { $entry.Status = 'TIMEOUT'; $entry.Notes += "Timed out after $($Task.Timeout)s; output (if any) is partial." }
                    elseif ($r.ExitCode -ne 0) { $entry.Status = 'FAILED'; $entry.Notes += "Non-zero exit code $($r.ExitCode)." }
                    elseif (-not $r.StdOut.Trim()) { $entry.Status = 'FAILED'; $entry.Notes += 'Exit code 0 but no output produced.' }
                    else { $entry.Status = 'OK' }
                }
            } else {
                $entry.Command = 'powershell (in-process)'; $entry.Arguments = ($Task.Script.ToString().Trim() -replace '\s+', ' ')
                $entry.ToolVersion = "PowerShell $($PSVersionTable.PSVersion)"
                $errs = @(); $data = $null
                $data = & $Task.Script 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $errs += $_.Exception.Message } else { $_ } }
                $data = @($data)
                foreach ($e in ($errs | Select-Object -Unique)) { $entry.Warnings += $e }
                if ($data.Count -gt 0) {
                    $f = Get-UniquePath $dir $Task.Id 'csv'
                    Write-As4File $f (($data | ConvertTo-Csv -NoTypeInformation) -join "`r`n"); $outFiles += $f
                    $fj = Get-UniquePath $dir $Task.Id 'json'
                    Write-As4File $fj ($data | ConvertTo-Json -Depth 4); $outFiles += $fj
                    $ft = Get-UniquePath $dir $Task.Id 'txt'
                    Write-As4File $ft ((($data | Format-List * | Out-String -Width 300)).Trim()); $outFiles += $ft
                    $entry.Status = 'OK'; $entry.Notes += "$($data.Count) record(s)."
                } elseif ($errs.Count) { $entry.Status = 'FAILED'; $entry.Notes += 'No data; errors raised.' }
                else { $entry.Status = 'OK'; $entry.Notes += 'Completed with zero records (nothing present or nothing visible to this account).' }
                $entry.ExitCode = 0
            }
        }
    } catch [OperationCanceledException] { $entry.Status = 'CANCELLED' }
    catch { $entry.Status = 'FAILED'; $entry.Notes += $_.Exception.Message; Write-As4Log ERROR "$($Task.Id): $($_.Exception.Message)" }
    $entry.EndUtc = if ($entry.EndUtc) { $entry.EndUtc } else { Get-UtcIso }
    if ($outFiles.Count) {
        $h = Register-As4Files $outFiles 'raw'
        $entry.Destination = @($outFiles | ForEach-Object { Get-RelPath $_ })
        $entry.Sha256 = @($h | ForEach-Object { $_.Sha256 })
    }
    Add-As4Manifest $entry
    $lvl = switch ($entry.Status) { 'OK' {'OK'} 'SKIPPED' {'WARN'} 'CANCELLED' {'WARN'} default {'ERROR'} }
    Write-As4Log $lvl "END   $($Task.Id) => $($entry.Status) $($entry.Notes -join ' ')"
    [pscustomobject]$entry
}

function Invoke-As4Batch {
    param([object[]]$Tasks, [scriptblock]$OnProgress, [string]$Label = 'batch')
    Start-As4Run $Label | Out-Null
    $i = 0; $res = @()
    foreach ($t in $Tasks) {
        $i++
        if ($OnProgress) { & $OnProgress $i $Tasks.Count $t }
        if ($global:Cancel) {
            $e = [ordered]@{ TaskId = $t.Id; Name = $t.Name; Category = $t.Folder; Status = 'CANCELLED'; StartUtc = Get-UtcIso; EndUtc = Get-UtcIso; Notes = @('Run cancelled by analyst before this task started.') }
            Add-As4Manifest $e; $res += [pscustomobject]$e; continue
        }
        try { $res += Invoke-As4Task $t } catch { Write-As4Log ERROR "$($t.Id) crashed: $($_.Exception.Message)" }   # one failure never stops the rest
    }
    Stop-As4Run
    $res
}

# ---------- tool registry ----------
function Get-As4Tools {
    $cfg = Join-Path $global:P.Config 'tools.json'
    if (-not (Test-Path -LiteralPath $cfg)) { return @() }
    $known = @{}
    $kf = Join-Path $global:P.Config 'tools_manifest.json'
    if (Test-Path -LiteralPath $kf) { try { foreach ($k in (Get-Content -LiteralPath $kf -Raw | ConvertFrom-Json)) { $known[$k.Id] = $k } } catch {} }
    foreach ($t in (Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json)) {
        $dir = Join-Path $global:P.Tools $t.Folder
        $found = $null
        if (Test-Path -LiteralPath $dir) {
            $pats = @($t.Patterns); if (-not [Environment]::Is64BitOperatingSystem) { $pats = @($pats | Sort-Object @{ e = { if ($_ -match 'x86|32') { 0 } else { 1 } } }) }
            foreach ($pat in $pats) {
                $found = Get-ChildItem -LiteralPath $dir -Recurse -File -Filter $pat -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(sigma|rules)\\' } | Select-Object -First 1
                if ($found) { break }
            }
        }
        $ver = $null; $sha = $null; $status = 'MISSING'
        if ($found) {
            $status = 'PRESENT'
            try { $ver = $found.VersionInfo.FileVersion } catch {}
            $sha = $null
            if ($known.ContainsKey($t.Id)) {
                $sha = Get-As4Sha256 $found.FullName
                $status = if ($known[$t.Id].Sha256 -eq $sha) { 'PRESENT_VERIFIED' } else { 'PRESENT_HASH_MISMATCH' }
            } else { $status = 'PRESENT_UNVERIFIED' }
        }
        [pscustomobject]@{ Id = $t.Id; Name = $t.Name; Folder = $t.Folder; Status = $status; Path = if ($found) { $found.FullName } else { $null }
            FileVersion = $ver; Sha256 = $sha; License = $t.License; Redistribution = $t.Redistribution; Source = $t.Source; Notes = $t.Notes; Required = $t.Required; Launch = [bool]$t.Launch }
    }
}

function Get-As4Tool { param([string]$Id) Get-As4Tools | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 }

function Get-DiskFreeBytes { param([string]$Path) try { $r = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)); (New-Object IO.DriveInfo($r)).AvailableFreeSpace } catch { $null } }

# ---------- shared entry helpers and task constructors ----------
function New-As4Entry {
    param([string]$Id, [string]$Name, [string]$Category, [string]$Source = 'live system')
    [ordered]@{ TaskId = $Id; Name = $Name; Category = $Category; Status = 'FAILED'; StartUtc = Get-UtcIso; EndUtc = $null; ExitCode = $null
        Command = $null; Arguments = $null; ToolVersion = $null; Source = $Source; Destination = @(); Sha256 = @(); Notes = @(); Warnings = @() }
}

function Complete-As4Entry {
    param($Entry, [string[]]$Files, [string]$Kind = 'raw')
    $Entry.EndUtc = Get-UtcIso
    $Files = @($Files | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($Files.Count) {
        $h = Register-As4Files $Files $Kind
        $Entry.Destination = @($Files | ForEach-Object { Get-RelPath $_ }); $Entry.Sha256 = @($h | ForEach-Object { $_.Sha256 })
    }
    Add-As4Manifest $Entry
    $lvl = switch ($Entry.Status) { 'OK' {'OK'} 'SKIPPED' {'WARN'} 'CANCELLED' {'WARN'} default {'ERROR'} }
    Write-As4Log $lvl "$($Entry.TaskId) => $($Entry.Status) $(@($Entry.Notes) -join ' ')"
    [pscustomobject]$Entry
}

# AS4 IR Tool - Chainsaw, KAPE, memory, FTK Imager, YARA integrations. ASCII only.
# Nothing is downloaded. A tool is only used if its real binary exists under tools\.

function Get-As4OpStatusFromResult {
    param($R)
    if ($R.Error) { return 'SKIPPED' }
    if ($R.Cancelled) { return 'CANCELLED' }
    if ($R.TimedOut) { return 'TIMEOUT' }
    if ($R.ExitCode -eq 0) { return 'OK' }
    'FAILED'
}

function Test-BlockedMessage { param([string]$m) ($m -match '(?i)application control|blocked|policy|not trusted|virus|Smart App') }

# ================= CHAINSAW =================

# AS4 IR Tool - Quick Response and Malware/Persistence triage task catalogs. ASCII only.
# All tasks are read-only collection. Nothing here terminates, deletes, quarantines or modifies anything.

function N { param($Id,$Name,$Folder,$Exe,$Arguments,$Desc,$Why='',$Ext='txt',$Timeout=120,$Admin='none',$Quick=$false,$Sensitive=$false)
    New-As4Task @{ Id=$Id; Name=$Name; Folder=$Folder; Type='native'; Exe=$Exe; Args=@($Arguments); Desc=$Desc; Why=$Why; Ext=$Ext; Timeout=$Timeout; Admin=$Admin; Quick=$Quick; Sensitive=$Sensitive } }

function S { param($Id,$Name,$Folder,[scriptblock]$Script,$Desc,$Why='',$Admin='none',$Quick=$false,$Sensitive=$false,$Timeout=300)
    New-As4Task @{ Id=$Id; Name=$Name; Folder=$Folder; Type='ps'; Script=$Script; Desc=$Desc; Why=$Why; Admin=$Admin; Quick=$Quick; Sensitive=$Sensitive; Timeout=$Timeout } }

# ---------- tool runtime libraries (so tools start on machines without the Visual C++ redistributable) ----------
$global:RtPattern = '^(msvcr\d+|msvcp\d+|vcruntime\d+(_\d+)?|mfc\d+\w*|mfcm\d+\w*|atl\d+|concrt\d+|vcomp\d+)\.dll$'
$global:RtChecked = @{}

function Get-PeInfo {
    # Reads a PE file header and returns its machine type and the DLL names it imports (no loading, no execution).
    param([string]$Path)
    try { $b = [IO.File]::ReadAllBytes($Path) } catch { return $null }
    if ($b.Length -lt 512 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { return $null }
    $pe = [BitConverter]::ToInt32($b, 0x3C); if ($pe -lt 0 -or $pe + 256 -gt $b.Length -or [BitConverter]::ToUInt32($b, $pe) -ne 0x4550) { return $null }
    $mach = [BitConverter]::ToUInt16($b, $pe + 4); $nsec = [BitConverter]::ToUInt16($b, $pe + 6); $osz = [BitConverter]::ToUInt16($b, $pe + 20); $opt = $pe + 24; $magic = [BitConverter]::ToUInt16($b, $opt)
    $dd = if ($magic -eq 0x20B) { $opt + 112 } else { $opt + 96 }; $imp = [BitConverter]::ToUInt32($b, $dd + 8)
    $names = @()
    if ($imp -ne 0) {
        $sec = $opt + $osz; $map = @(); for ($i = 0; $i -lt $nsec; $i++) { $o = $sec + 40 * $i; $map += [pscustomobject]@{ VA = [BitConverter]::ToUInt32($b, $o + 12); Size = [Math]::Max([BitConverter]::ToUInt32($b, $o + 8), [BitConverter]::ToUInt32($b, $o + 16)); Raw = [BitConverter]::ToUInt32($b, $o + 20) } }
        $r2o = { param($rva) foreach ($s in $map) { if ($rva -ge $s.VA -and $rva -lt $s.VA + $s.Size) { return [int]($rva - $s.VA + $s.Raw) } }; -1 }
        $o = & $r2o $imp
        while ($o -ge 0 -and $o + 20 -le $b.Length) { $n = [BitConverter]::ToUInt32($b, $o + 12); if ($n -eq 0) { break }; $no = & $r2o $n; if ($no -lt 0) { break }; $e = $no; while ($e -lt $b.Length -and $b[$e] -ne 0) { $e++ }; $names += [Text.Encoding]::ASCII.GetString($b, $no, $e - $no); $o += 20 }
    }
    [pscustomobject]@{ Machine = $mach; X64 = ($mach -eq 0x8664); Imports = $names; Managed = ($names -contains 'mscoree.dll') }
}

function Repair-As4ToolRuntimes {
    # For each folder: any Visual C++ runtime DLL that a program there imports but that is not beside it is copied from tools\_runtime\x64.
    # Nothing is installed and nothing outside the AS4 folder is touched. Returns one row per DLL that was copied or could not be supplied.
    param([string[]]$Folders)
    $rt = Join-Path $global:P.Tools '_runtime\x64'; $res = @()
    foreach ($fo in $Folders) {
        if (-not $fo -or -not (Test-Path -LiteralPath $fo -PathType Container)) { continue }
        for ($pass = 0; $pass -lt 3; $pass++) {
            $changed = $false
            foreach ($f in (Get-ChildItem -LiteralPath $fo -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.exe', '.dll' })) {
                $info = Get-PeInfo $f.FullName; if (-not $info -or -not $info.X64) { continue }
                foreach ($d in ($info.Imports | Where-Object { $_ -match $global:RtPattern } | Select-Object -Unique)) {
                    if (Test-Path -LiteralPath (Join-Path $fo $d)) { continue }
                    $src = Join-Path $rt $d
                    if (Test-Path -LiteralPath $src) {
                        try { Copy-Item -LiteralPath $src -Destination (Join-Path $fo $d) -ErrorAction Stop; $res += [pscustomobject]@{ Folder = $fo; Dll = $d; Needed = $f.Name; Action = 'copied from tools\_runtime'; Ok = $true }; $changed = $true }
                        catch { $res += [pscustomobject]@{ Folder = $fo; Dll = $d; Needed = $f.Name; Action = "could not copy ($($_.Exception.Message)); PATH fallback is used"; Ok = $false } }
                    } elseif (-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32\$d"))) { $res += [pscustomobject]@{ Folder = $fo; Dll = $d; Needed = $f.Name; Action = 'missing: not in tools\_runtime and not on this machine'; Ok = $false } }
                }
            }
            if (-not $changed) { break }
        }
    }
    $res
}