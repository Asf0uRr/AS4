<#
 Builds a clean, publishable package: dist\AS4_IR_Tool_<version>.zip + SHA256SUMS.txt
 Included : app, tasks, config (without the community YARA rules), docs, scripts, launcher exes, and the tools whose licences allow redistribution
            (Hayabusa AGPL-3.0, Chainsaw GPL-3.0 + Sigma DRL, YARA BSD-3, WinPmem Apache-2.0).
 Left out : KAPE, FTK Imager, Sysinternals, Volatility, Belkasoft, NirSoft, NetworkMiner, Arsenal, ExifTool (not redistributable here or not needed),
            every case in output\, test leftovers, the community YARA rule set (mixed or unknown licences), third-party PDFs.
 Users add the missing tools with scripts\Get-Tools.ps1 (free ones) or by hand (KAPE, FTK Imager); see tools\README.md in the package.
#>
param([string]$Version = '1.1.0')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
# the staging path is kept short because some rule files have long names
$dist = Join-Path $root 'dist'; $name = "AS4_IR_Tool_$Version"; $stage = Join-Path ([IO.Path]::GetTempPath()) ("a4r" + [guid]::NewGuid().ToString('N').Substring(0, 6)); $pkg = Join-Path $stage $name
New-Item -ItemType Directory -Path $pkg -Force | Out-Null; New-Item -ItemType Directory -Path $dist -Force | Out-Null
function Copy-Tree($from, $to, [string[]]$excludeDirs = @(), [string[]]$excludeFiles = @()) {
    $xd = @(); foreach ($d in $excludeDirs) { $xd += @('/XD', $d) }; $xf = @(); if ($excludeFiles.Count) { $xf = @('/XF') + $excludeFiles }
    & robocopy $from $to /E /NFL /NDL /NJH /NJS /NP @xd @xf | Out-Null; if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $from" } }

foreach ($d in 'app', 'tasks', 'scripts') { Copy-Tree (Join-Path $root $d) (Join-Path $pkg $d) }
Copy-Tree (Join-Path $root 'docs') (Join-Path $pkg 'docs') @() @('*.pdf')
Copy-Tree (Join-Path $root 'config') (Join-Path $pkg 'config') @((Join-Path $root 'config\rules\yara\community')) @('tools_manifest.json')
foreach ($f in 'README.md', 'LICENSE', 'CHANGELOG.md', 'SECURITY.md', 'AS4_IR_Tool.exe', 'AS4_IR_Tool_Admin.exe', 'AS4_IR_Tool_CLI.exe') { if (Test-Path (Join-Path $root $f)) { Copy-Item (Join-Path $root $f) $pkg } }
# tools that may be redistributed
Copy-Tree (Join-Path $root 'tools\Hayabusa') (Join-Path $pkg 'tools\Hayabusa')
Copy-Tree (Join-Path $root 'tools\Chainsaw\chainsaw') (Join-Path $pkg 'tools\Chainsaw\chainsaw') @('regression_data') @('*apple-darwin*', '*linux*')   # regression_data = Sigma test samples, not needed to hunt
Copy-Tree (Join-Path $root 'tools\YARA') (Join-Path $pkg 'tools\YARA')
Copy-Tree (Join-Path $root 'tools\_runtime') (Join-Path $pkg 'tools\_runtime')   # unmodified Microsoft Visual C++ runtime DLLs
New-Item -ItemType Directory -Path (Join-Path $pkg 'tools\MemoryAcquisition') -Force | Out-Null; Copy-Item (Join-Path $root 'tools\MemoryAcquisition\winpmem_mini_x64_rc2.exe') (Join-Path $pkg 'tools\MemoryAcquisition')
# hash manifest limited to what is in the package
$man = Get-Content (Join-Path $root 'config\tools_manifest.json') -Raw | ConvertFrom-Json; $keep = @(foreach ($m in $man) { if (Test-Path (Join-Path $pkg $m.File)) { $m } })
($keep | ConvertTo-Json -Depth 5) | Set-Content (Join-Path $pkg 'config\tools_manifest.json') -Encoding UTF8
# placeholders so the folders exist
$ph = @{ 'tools\KAPE' = 'Put kape.exe with its Targets and Modules folders here (Kroll registration form; not redistributable). Then run scripts\Prepare-Tools.ps1 -Register -Tool kape -File tools\KAPE\kape.exe'
         'tools\DiskForensics' = 'Put FTK Imager here, for example tools\DiskForensics\FTK Imager\FTK Imager.exe (Exterro registration form). Then run scripts\Prepare-Tools.ps1 -Register -Tool ftkimager -File "tools\DiskForensics\FTK Imager\FTK Imager.exe"'
         'tools\Sysinternals' = 'Run scripts\Get-Tools.ps1 on a machine with internet to fetch Autoruns, Sigcheck, Handle, ListDLLs, PsTools, TCPView and Strings from Microsoft.'
         'tools\Volatility3' = 'Run scripts\Get-Tools.ps1 to fetch Volatility 3 (and the optional 800 MB Windows symbol pack).'
         'tools\Other' = 'Optional extra tools. Add an entry for each in config\tools.json and register it with scripts\Prepare-Tools.ps1.'
         'output' = 'Cases are created here, one folder per case name. Nothing else is stored here.' }
foreach ($k in $ph.Keys) { $d = Join-Path $pkg $k; New-Item -ItemType Directory -Path $d -Force | Out-Null; Set-Content (Join-Path $d 'README.txt') $ph[$k] -Encoding ASCII }
Set-Content (Join-Path $pkg 'tools\README.md') "# tools`r`n`r`nIncluded in this package: Hayabusa, Chainsaw (with Sigma rules), YARA, WinPmem.`r`nNot included (licence or size): KAPE, FTK Imager, Sysinternals, Volatility 3 and others. Add them as described in each folder's README.txt, or run ``scripts\Get-Tools.ps1`` for the freely downloadable ones. Every tool is optional: AS4 reports what is missing and keeps working.`r`n" -Encoding ASCII

# safety checks: nothing that must not be published
$forbidden = 'kape.exe', 'gkape.exe', 'FTK Imager.exe', 'autorunsc64.exe', 'vol.exe', 'RamCapture64.exe', 'NetworkMiner.exe', 'ArsenalImageMounter.exe', 'LastActivityView.exe', '*.pdf'
foreach ($f in $forbidden) { $hit = Get-ChildItem $pkg -Recurse -File -Filter $f -ErrorAction SilentlyContinue | Select-Object -First 1; if ($hit) { throw "Release contains a file that must not be published: $($hit.FullName)" } }
$caseData = Get-ChildItem (Join-Path $pkg 'output') -Recurse -File | Where-Object Name -ne 'README.txt'; if ($caseData) { throw 'Release contains case data.' }
$pers = Get-ChildItem $pkg -Recurse -File -Include *.md, *.ps1, *.json, *.cs, *.cmd, *.txt -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(tools|licenses)\\' -and $_.Name -ne 'New-Release.ps1' } | Select-String -Pattern 'Asf0uRr|NCSC|baraa|@gmail' -ErrorAction SilentlyContinue
if ($pers) { throw "Personal data found: $($pers[0].Path):$($pers[0].LineNumber)" }

$zip = Join-Path $dist "$name.zip"; if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression; Add-Type -AssemblyName System.IO.Compression.FileSystem
# write entries with forward slashes (the zip standard) so 7-Zip, macOS and Linux extract it correctly
$fs = [IO.File]::Create($zip); $arc = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
foreach ($f in (Get-ChildItem $stage -Recurse -File -Force)) { $entry = $f.FullName.Substring($stage.Length + 1).Replace('\', '/'); [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arc, $f.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal) }
$arc.Dispose(); $fs.Dispose()
$za = [IO.Compression.ZipFile]::OpenRead($zip); $zn = @($za.Entries | Where-Object { $_.FullName -notmatch '[/\\]$' }).Count; $za.Dispose()
$sn = (Get-ChildItem $pkg -Recurse -File -Force -ErrorAction Stop).Count
if ($zn -ne $sn) { throw "The zip has $zn files but the package has $sn. Not publishing a partial archive." }
$h = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower(); Set-Content (Join-Path $dist 'SHA256SUMS.txt') "$h  $name.zip" -Encoding ASCII
$cnt = (Get-ChildItem $pkg -Recurse -File -Force).Count; $mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
$empty = Join-Path ([IO.Path]::GetTempPath()) ("as4_empty_" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $empty -Force | Out-Null; & robocopy $empty $stage /MIR /NFL /NDL /NJH /NJS /NP | Out-Null; Remove-Item $stage, $empty -Recurse -Force -ErrorAction SilentlyContinue   # robocopy clears deep paths that Remove-Item cannot
"{0}  {1} MB  {2} files  SHA-256 {3}" -f $zip, $mb, $cnt, $h
