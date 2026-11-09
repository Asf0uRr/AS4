# AS4 IR Tool - Memory

# ================= MEMORY / FTK / VOLATILITY =================
function Get-MemoryTools {
    foreach ($id in 'winpmem', 'ftkimager', 'volatility3', 'dumpit') { Get-As4Tool $id }
}

function Test-MemorySpace {
    param([string]$DestDir)
    $ram = 0; try { $ram = [int64](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory } catch {}
    $free = Get-DiskFreeBytes $DestDir
    [pscustomobject]@{ RamBytes = $ram; FreeBytes = $free; NeededBytes = [int64]($ram * 1.05); Sufficient = [bool]($free -and $ram -and $free -gt ($ram * 1.05 + 1GB)); Note = 'Raw memory images are about the size of installed RAM; 5% + 1 GB margin required.' }
}

function Get-MemToolHelp {
    param($Tool)
    if (-not $Tool.Path) { return 'Tool not present.' }
    $r = Invoke-As4Native -Exe $Tool.Path -Arguments @('--help') -TimeoutSec 30
    if ($r.Error) { return "Cannot execute: $($r.Error)" }
    $t = ($r.StdOut + "`n" + $r.StdErr).Trim(); if (-not $t) { $r = Invoke-As4Native -Exe $Tool.Path -Arguments @('-h') -TimeoutSec 30; $t = ($r.StdOut + "`n" + $r.StdErr).Trim() }
    $t
}

function Invoke-MemoryAcquisition {
    # ArgTemplate must contain {OUT}; analyst reviews it against the tool's own help first.
    param([string]$ToolId = 'winpmem', [string]$DestDir, [string]$ArgTemplate)
    $t = Get-As4Tool $ToolId
    $e = New-As4Entry 'memory_acquisition' "Memory acquisition ($ToolId)" $global:CaseFolders.Mem
    Start-As4Run 'memory' | Out-Null; $files = @()
    try {
        if (-not $t -or -not $t.Path) { $e.Status = 'SKIPPED'; $e.Notes += "$ToolId binary not found under tools\. AS4 will not download it; see docs\TOOLS_INVENTORY.md."; return (Complete-As4Entry $e @()) }
        if ($t.Status -eq 'PRESENT_HASH_MISMATCH') { $e.Status = 'SKIPPED'; $e.Notes += 'Binary hash does not match the recorded manifest - refusing to run unverified acquisition binary.'; return (Complete-As4Entry $e @()) }
        if ($t.Status -eq 'PRESENT_UNVERIFIED') { $e.Warnings += 'Binary is not registered in config\tools_manifest.json (provenance unverified). Register it with scripts\Prepare-Tools.ps1 on the analyst workstation.' }
        if (-not (Test-As4Admin)) { $e.Status = 'SKIPPED'; $e.Notes += 'Memory acquisition requires administrator.'; return (Complete-As4Entry $e @()) }
        if (-not $DestDir) { $DestDir = Get-CaseFolder 'Mem' }
        if (-not (Test-Path -LiteralPath $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }
        $sp = Test-MemorySpace $DestDir
        if (-not $sp.Sufficient) { $e.Status = 'SKIPPED'; $e.Notes += "Insufficient space: need ~$([math]::Round($sp.NeededBytes/1GB,1)) GB, have $([math]::Round($sp.FreeBytes/1GB,1)) GB at $DestDir."; return (Complete-As4Entry $e @()) }
        if ($ArgTemplate -notmatch '\{OUT\}') { throw 'Argument template must contain {OUT}.' }
        $out = Get-UniquePath $DestDir ("memory_" + $env:COMPUTERNAME) 'raw'
        $a = @($ArgTemplate -split ' ' | Where-Object { $_ } | ForEach-Object { $_ -replace '\{OUT\}', $out })
        $e.Command = $t.Path; $e.Arguments = ConvertTo-ArgString $a; $e.ToolVersion = $t.FileVersion
        $e.Warnings += 'Memory acquisition is intrusive: it loads a driver/executes code on the live system and the image may contain credentials and personal data.'
        $r = Invoke-As4Native -Exe $t.Path -Arguments $a -TimeoutSec 0
        $e.ExitCode = $r.ExitCode; $e.StartUtc = $r.StartUtc
        $lf = Get-UniquePath (Get-CaseFolder 'Mem') 'acquisition_log' 'txt'; Write-As4File $lf ("cmd: $($t.Path) $($e.Arguments)`r`nstart: $($r.StartUtc)`r`nend: $($r.EndUtc)`r`nexit: $($r.ExitCode)`r`n--- stdout ---`r`n$($r.StdOut)`r`n--- stderr ---`r`n$($r.StdErr)"); $files += $lf
        $st = Get-As4OpStatusFromResult $r
        if ($st -eq 'OK') {
            if ((Test-Path -LiteralPath $out) -and (Get-Item -LiteralPath $out).Length -gt 100MB) {
                $h = Get-As4Sha256 $out; $sz = (Get-Item -LiteralPath $out).Length
                $hf = Get-UniquePath (Get-CaseFolder 'Mem') 'memory_image_sha256' 'txt'; Write-As4File $hf "$h  $out  ($sz bytes)  acquired $($r.EndUtc)`r`n"; $files += $hf
                $e.Notes += "Image: $out ($sz bytes) SHA-256 $h"; $e.Destination = @($out)
                $files += $out
            } else { $st = 'FAILED'; $e.Notes += 'Tool exited 0 but no plausible memory image exists at the destination; not treated as success.' }
        } else { $e.Notes += "Acquisition status $st exit=$($r.ExitCode)" }
        $e.Status = $st
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e $files; Stop-As4Run; $res
}

function Start-As4GuiTool {
    # Launch an interactive tool (e.g. FTK Imager). Recorded in manifest; analyst operates it.
    param([string]$ToolId)
    $t = Get-As4Tool $ToolId
    $e = New-As4Entry "launch_$ToolId" "Launch $ToolId" $global:CaseFolders.Disk
    Start-As4Run "launch-$ToolId" | Out-Null
    try {
        if (-not $t -or -not $t.Path) { $e.Status = 'SKIPPED'; $e.Notes += "$ToolId not found under tools\ (licensed/obtained separately)."; }
        elseif ($t.Status -eq 'PRESENT_HASH_MISMATCH') { $e.Status = 'SKIPPED'; $e.Notes += 'Hash mismatch against manifest; refusing to launch.' }
        else {
            $e.Command = $t.Path; $e.ToolVersion = $t.FileVersion
            if ($t.Status -eq 'PRESENT_UNVERIFIED') { $e.Warnings += 'Provenance unverified (not in tools_manifest.json).' }
            foreach ($x in @(Repair-As4ToolRuntimes -Folders @(Split-Path $t.Path))) { if ($x.Ok) { $e.Notes += "Runtime library $($x.Dll) copied next to $ToolId from tools\_runtime." } else { $e.Warnings += "$ToolId needs $($x.Dll) ($($x.Action))." } }
            $p = Start-Process -FilePath $t.Path -WorkingDirectory (Split-Path $t.Path) -PassThru
            $e.Status = 'OK'; $e.Notes += "Launched interactively (PID $($p.Id)). Imaging actions inside the tool are performed and recorded by the analyst; AS4 cannot verify them."
        }
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e @(); Stop-As4Run; $res
}

function Start-FtkImager {
    # Opens FTK Imager with the case folder ready. FTK Imager is operated by the analyst:
    #   Memory:  File > Capture Memory...   Disk: File > Create Disk Image...
    param([ValidateSet('memory', 'disk')][string]$Mode)
    $dest = Get-CaseFolder $(if ($Mode -eq 'memory') { 'Mem' } else { 'Disk' })
    $e = New-As4Entry "ftk_$Mode" $(if ($Mode -eq 'memory') { 'FTK Imager - memory capture' } else { 'FTK Imager - disk image' }) $(if ($Mode -eq 'memory') { $global:CaseFolders.Mem } else { $global:CaseFolders.Disk })
    Start-As4Run "ftk-$Mode" | Out-Null
    $t = Get-As4Tool 'ftkimager'
    try {
        if (-not $t -or -not $t.Path) { $e.Status = 'SKIPPED'; $e.Notes += 'FTK Imager is not in tools\DiskForensics. Download it from Exterro (registration required) and run scripts\Prepare-Tools.ps1 -Register.' }
        elseif ($t.Status -eq 'PRESENT_HASH_MISMATCH') { $e.Status = 'SKIPPED'; $e.Notes += 'FTK Imager does not match its recorded hash.' }
        else {
            $fix = @(Repair-As4ToolRuntimes -Folders @(Split-Path $t.Path)); foreach ($x in $fix) { if ($x.Ok) { $e.Notes += "Runtime library $($x.Dll) was missing next to FTK Imager and was copied from tools\_runtime." } else { $e.Warnings += "FTK Imager needs $($x.Dll) ($($x.Action))." } }
            $stillMissing = @($fix | Where-Object { -not $_.Ok -and $_.Action -like 'missing*' })
            if ($stillMissing.Count) { $e.Status = 'FAILED'; $e.Notes += "FTK Imager cannot start: $(($stillMissing | ForEach-Object { $_.Dll }) -join ', ') not found. Copy those files from a Visual C++ redistributable into the FTK Imager folder, or install the redistributable on this machine."; $r0 = Complete-As4Entry $e @(); Stop-As4Run; return $r0 }
            try { Set-Clipboard -Value $dest } catch {}
            $global:FtkStart = Get-Date
            # FTK Imager always requires elevation; ask Windows (UAC) when AS4 itself is not elevated.
            if (Test-As4Admin) { $p = Start-Process -FilePath $t.Path -WorkingDirectory (Split-Path $t.Path) -PassThru }
            else { $p = Start-Process -FilePath $t.Path -WorkingDirectory (Split-Path $t.Path) -Verb RunAs -PassThru; $e.Warnings += 'Started through a UAC prompt (AS4 is not elevated).' }
            $e.Command = $t.Path; $e.ToolVersion = $t.FileVersion; $e.Status = 'OK'
            $e.Notes += "FTK Imager started (PID $($p.Id)). Destination folder: $dest (copied to clipboard). After imaging, use Register FTK output to hash and record the files."
            if ($Mode -eq 'memory' -and -not (Test-As4Admin)) { $e.Warnings += 'Not elevated: FTK Imager cannot capture memory without administrator rights.' }
        }
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $r = Complete-As4Entry $e @(); Stop-As4Run; $r
}

function Register-FtkOutput {
    # Hashes and records what FTK Imager wrote into the case folder (or another folder you name).
    param([ValidateSet('memory', 'disk')][string]$Mode, [string]$Folder, $Since)
    if (-not $Folder) { $Folder = Get-CaseFolder $(if ($Mode -eq 'memory') { 'Mem' } else { 'Disk' }) }
    $e = New-As4Entry "ftk_${Mode}_register" "FTK Imager output ($Mode)" $(if ($Mode -eq 'memory') { $global:CaseFolders.Mem } else { $global:CaseFolders.Disk }) 'FTK Imager'
    Start-As4Run "ftk-register-$Mode" | Out-Null; $files = @()
    try {
        if (-not (Test-Path -LiteralPath $Folder)) { throw "Folder not found: $Folder" }
        if (-not $Since) { $Since = $global:FtkStart }
        $items = @(Get-ChildItem -LiteralPath $Folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { (-not $Since -or $_.LastWriteTime -ge $Since) -and $_.Name -notmatch '^(seal_|hashes\.csv|case\.json|manifest\.jsonl|session\.log)' })
        $img = @($items | Where-Object { $_.Extension -match '^\.(mem|raw|dmp|dd|bin|e01|ex01|aff4|vmdk|\d{3})$' -and $_.Length -gt 0 })
        if (-not $img.Count) { $e.Status = 'FAILED'; $e.Notes += "No image file (.mem .raw .dmp .dd .E01 .001 ...) found in $Folder$(if ($Since) { " newer than $Since" })."; }
        else {
            $e.Command = 'AS4 register'; $e.Arguments = $Folder
            foreach ($f in $items) { $files += $f.FullName }
            $e.Notes += "$($img.Count) image file(s), $([math]::Round((($img | Measure-Object Length -Sum).Sum) / 1GB, 2)) GB. SHA-256 recorded in the hash ledger; FTK's own hash report (.txt) is kept alongside."
            $e.Status = 'OK'
        }
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $r = Complete-As4Entry $e $files; Stop-As4Run; $r
}

function Invoke-FtkCliImage {
    # Optional: bundled FTK Imager command-line (ftkimager.exe) for disk imaging. Flags are used only if its help lists them.
    param([string]$Source, [string]$Name = 'disk_image', [switch]$Verify)
    $t = Get-As4Tool 'ftkimager-cli'
    $e = New-As4Entry 'ftk_cli_image' 'FTK Imager CLI - disk image' $global:CaseFolders.Disk 'selected source'
    Start-As4Run 'ftk-cli' | Out-Null; $files = @()
    try {
        if (-not $t -or -not $t.Path) { $e.Status = 'SKIPPED'; $e.Notes += 'FTK Imager CLI (ftkimager.exe) is not in tools\DiskForensics.'; return (Complete-As4Entry $e @()) }
        if (-not (Test-As4Admin)) { $e.Status = 'SKIPPED'; $e.Notes += 'Disk imaging needs administrator.'; return (Complete-As4Entry $e @()) }
        if (-not $Source) { throw 'Choose a source (for example \\.\PHYSICALDRIVE1 or a volume).' }
        $h = Invoke-As4Native -Exe $t.Path -Arguments @('--help') -TimeoutSec 30; $help = $h.StdOut + $h.StdErr
        $dest = Join-Path (Get-CaseFolder 'Disk') ($Name -replace '[^A-Za-z0-9._-]', '_')
        $a = @($Source, $dest)
        if ($help -match '--e01') { $a += '--e01' }
        if ($Verify -and $help -match '--verify') { $a += '--verify' }
        $e.Command = $t.Path; $e.Arguments = ConvertTo-ArgString $a; $e.ToolVersion = $t.FileVersion
        $r = Invoke-As4Native -Exe $t.Path -Arguments $a -TimeoutSec 0
        $lf = Get-UniquePath (Get-CaseFolder 'Disk') 'ftkimager_log' 'txt'; Write-As4File $lf ($r.StdOut + "`r`n" + $r.StdErr); $files += $lf
        $e.ExitCode = $r.ExitCode; $e.Status = Get-As4OpStatusFromResult $r
        foreach ($f in (Get-ChildItem -LiteralPath (Get-CaseFolder 'Disk') -File | Where-Object { $_.Name -like ((Split-Path $dest -Leaf) + '*') })) { $files += $f.FullName }
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e $files; Stop-As4Run; $res
}

function Invoke-Volatility {
    param([string]$Dump, [string]$Plugin = 'windows.info')
    $t = Get-As4Tool 'volatility3'
    $e = New-As4Entry 'volatility' "Volatility 3: $Plugin" $global:CaseFolders.Mem 'existing memory dump'
    Start-As4Run 'volatility' | Out-Null; $files = @()
    try {
        if (-not $t -or -not $t.Path) { $e.Status = 'SKIPPED'; $e.Notes += 'Volatility 3 (vol.exe) is not in tools\Volatility3.'; return (Complete-As4Entry $e @()) }
        if (-not (Test-Path -LiteralPath $Dump -PathType Leaf)) { throw "Dump not found: $Dump" }
        if ($Plugin -notmatch '^[A-Za-z0-9_.]+$') { throw 'Invalid plugin name.' }
        $a = @()
        $sym = Join-Path (Split-Path $t.Path) 'symbols'
        if (Test-Path -LiteralPath $sym) { $a += @('--symbol-dirs', $sym) }
        $h = Invoke-As4Native -Exe $t.Path -Arguments @('--help') -TimeoutSec 60
        if (($h.StdOut + $h.StdErr) -match '--offline') { $a += '--offline' }
        $a += @('-f', $Dump, $Plugin)
        $e.Command = $t.Path; $e.Arguments = ConvertTo-ArgString $a; $e.ToolVersion = $t.FileVersion
        $r = Invoke-As4Native -Exe $t.Path -Arguments $a -TimeoutSec 3600
        $out = Get-UniquePath (Get-CaseFolder 'Mem') ("vol_" + $Plugin) 'txt'; Write-As4File $out ($r.StdOut + "`r`n" + $r.StdErr); $files += $out
        $e.ExitCode = $r.ExitCode; $e.Status = Get-As4OpStatusFromResult $r
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e $files 'derived'; Stop-As4Run; $res
}