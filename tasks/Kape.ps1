# AS4 IR Tool - Kape

# ================= KAPE =================
function Get-KapeInfo {
    $t = Get-As4Tool 'kape'
    $i = [ordered]@{ Present = $false; Path = $null; Dir = $null; Version = $null; Help = ''; Flags = @(); Targets = @(); Modules = @(); Runnable = $false; BlockReason = $null }
    if ($t -and $t.Path) {
        $i.Present = $true; $i.Path = $t.Path; $i.Dir = Split-Path $t.Path
        $h = Invoke-As4Native -Exe $t.Path -Arguments @('--help') -TimeoutSec 60
        if ($h.Error) { $i.BlockReason = $h.Error } else { $i.Runnable = $true; $i.Help = $h.StdOut + "`n" + $h.StdErr; $i.Flags = @([regex]::Matches($i.Help, '--[a-zA-Z][a-zA-Z0-9]*') | ForEach-Object { $_.Value } | Select-Object -Unique)
            if ($i.Help -match '(?i)KAPE\s+version\s+([0-9.]+)') { $i.Version = $Matches[1] } else { $i.Version = $t.FileVersion } }
        $parse = { param($dir, $pat) if (Test-Path $dir) { Get-ChildItem -LiteralPath $dir -Recurse -File -Filter $pat -ErrorAction SilentlyContinue | ForEach-Object { $d = ''; $m = Select-String -LiteralPath $_.FullName -Pattern '^\s*Description:\s*(.+)$' -List -ErrorAction SilentlyContinue; if ($m) { $d = $m.Matches[0].Groups[1].Value.Trim() }; [pscustomobject]@{ Name = $_.BaseName; Description = $d; File = $_.FullName } } } }
        $i.Targets = @(& $parse (Join-Path $i.Dir 'Targets') '*.tkape' | Sort-Object Name)
        $i.Modules = @(& $parse (Join-Path $i.Dir 'Modules') '*.mkape' | Sort-Object Name)
    }
    [pscustomobject]$i
}

function Get-KapeProfiles {
    $k = Get-KapeInfo; $names = @{}; foreach ($t in $k.Targets) { $names[$t.Name] = $true }; $mn = @{}; foreach ($m in $k.Modules) { $mn[$m.Name] = $true }
    foreach ($f in (Get-ChildItem $global:P.Profiles -Filter 'kape_*.json' -ErrorAction SilentlyContinue)) {
        $p = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        [pscustomobject]@{ Name = $p.Name; Description = $p.Description; Targets = @($p.Targets | Where-Object { $names.ContainsKey($_) }); MissingTargets = @($p.Targets | Where-Object { -not $names.ContainsKey($_) })
            Modules = @($p.Modules | Where-Object { $mn.ContainsKey($_) }); MissingModules = @($p.Modules | Where-Object { -not $mn.ContainsKey($_) }); Live = $p.Live }
    }
}

function Invoke-Kape {
    param([string]$Source = 'C:', [string[]]$Targets, [string[]]$Modules, [switch]$ProcessOnly, [string]$ModuleSource)
    $k = Get-KapeInfo
    $e = New-As4Entry 'kape' 'KAPE collection' $global:CaseFolders.Kape "source $Source"
    Start-As4Run 'kape' | Out-Null; $files = @()
    try {
        if (-not $k.Present) { $e.Status = 'SKIPPED'; $e.Notes += 'KAPE not found in tools\KAPE. KAPE is licensed software that is not redistributed by AS4; see docs\TOOLS_INVENTORY.md.'; return (Complete-As4Entry $e @()) }
        if (-not $k.Runnable) { $e.Status = 'SKIPPED'; $e.Notes += "KAPE cannot execute: $($k.BlockReason)"; return (Complete-As4Entry $e @()) }
        if (-not (Test-As4Admin)) { $e.Status = 'SKIPPED'; $e.Notes += 'KAPE requires administrator for live collection.'; return (Complete-As4Entry $e @()) }
        if (-not $Targets -and -not $Modules) { throw 'Select at least one Target or Module. AS4 never runs everything automatically.' }
        $valid = @{}; foreach ($t in $k.Targets) { $valid['t:' + $t.Name] = 1 }; foreach ($m in $k.Modules) { $valid['m:' + $m.Name] = 1 }
        foreach ($t in $Targets) { if (-not $valid.ContainsKey("t:$t")) { throw "Unknown KAPE target '$t' (not in bundled Targets folder)." } }
        foreach ($m in $Modules) { if (-not $valid.ContainsKey("m:$m")) { throw "Unknown KAPE module '$m' (not in bundled Modules folder)." } }
        $runDir = Join-Path (Get-CaseFolder 'Kape') $global:RunId
        $tdest = Join-Path $runDir 'targets'; $mdest = Join-Path $runDir 'modules'
        $need = 0; try { $di = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($Source + '\')); $need = $di.TotalSize - $di.AvailableFreeSpace } catch {}
        $free = Get-DiskFreeBytes $runDir
        $e.Notes += "Upper-bound size estimate: used space on source volume ~$([math]::Round($need/1GB,1)) GB (real output is usually far smaller); destination free ~$([math]::Round($free/1GB,1)) GB."
        $a = @()
        if (-not $ProcessOnly -and $Targets) { if ($k.Flags -notcontains '--tsource') { throw "Installed KAPE help does not list --tsource." }; $a += @('--tsource', $Source, '--tdest', $tdest, '--target', ($Targets -join ',')) }
        if ($Modules) { $msrc = if ($ModuleSource) { $ModuleSource } else { $tdest }; $a += @('--msource', $msrc, '--mdest', $mdest, '--module', ($Modules -join ',')) }
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $e.Command = $k.Path; $e.Arguments = ConvertTo-ArgString $a; $e.ToolVersion = $k.Version
        $r = Invoke-As4Native -Exe $k.Path -Arguments $a -TimeoutSec 14400 -WorkDir $k.Dir
        $so = Join-Path $runDir 'kape_stdout.txt'; Write-As4File $so $r.StdOut; $files += $so
        if ($r.StdErr.Trim()) { $se = Join-Path $runDir 'kape_stderr.txt'; Write-As4File $se $r.StdErr; $files += $se }
        $af = Join-Path $runDir 'kape_arguments.json'; Write-As4File $af ([ordered]@{ Exe = $k.Path; Args = $a; Targets = $Targets; Modules = $Modules; Source = $Source } | ConvertTo-Json); $files += $af
        foreach ($x in @(Get-ChildItem -LiteralPath $runDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $files -notcontains $_.FullName })) { $files += $x.FullName }
        $e.ExitCode = $r.ExitCode; $e.Status = Get-As4OpStatusFromResult $r
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e $files; Stop-As4Run; $res
}
