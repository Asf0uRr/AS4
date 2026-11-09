<#
 AS4 IR Tool - entry point. The root folder is derived from this file's location, so the folder can sit on any drive or path.
 Usage: AS4_IR_Tool_CLI.exe [-Cli | -Check] [-Batch quick|full|triage|evtx|hunt|first5|malware|logons|ransomware|insider|persistence|package -Case "name"]
#>
param(
    [switch]$Gui, [switch]$Cli, [switch]$Check, [switch]$SelfTest,
    [string]$Root, [string]$Batch, [Alias('Case','CaseId')][string]$CaseName, [string]$ScreenshotPath
)
$ErrorActionPreference = 'Continue'
$appDir = $PSScriptRoot
if (-not $Root) { $Root = Split-Path -Parent $appDir }

$parts = @((Join-Path $appDir 'Core.ps1'))
foreach ($f in 'QuickResponse', 'Persistence', 'EventLogs', 'Artifacts', 'Hayabusa', 'QuickScan', 'Chainsaw', 'Kape', 'Memory', 'Yara', 'IocSearch', 'Timeline', 'Integrity', 'Report', 'LiveHunt', 'LiveReport', 'LiveWatch', 'Scenarios', 'Package') { $parts += (Join-Path $Root "tasks\$f.ps1") }
$parts += (Join-Path $appDir 'Cli.ps1'); $parts += (Join-Path $appDir 'Gui.ps1'); $parts += (Join-Path $appDir 'GuiLive.ps1'); $parts += (Join-Path $appDir 'CliLive.ps1')
foreach ($p in $parts) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "Missing file: $p" -ForegroundColor Red; exit 2 }
    . $p
}
Initialize-As4 -Root $Root
$env:AS4_TARGET_MODE = '1'     # scripts\Prepare-Tools.ps1 refuses to run when this is set (no downloads on endpoints)

function Test-As4Environment {
    $r = @()
    $r += [pscustomobject]@{ Check = 'PowerShell 5.1 or later'; Result = $(if ($PSVersionTable.PSVersion -ge [version]'5.1') { 'PASS' } else { 'FAIL' }); Detail = $PSVersionTable.PSVersion.ToString() }
    $os = [Environment]::OSVersion.Version; $osName = ''; try { $osName = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch {}
    $r += [pscustomobject]@{ Check = 'Windows version'; Result = $(if ($os.Major -ge 10) { 'PASS' } elseif ($os.Major -eq 6) { 'WARN' } else { 'FAIL' }); Detail = "$osName ($($os.ToString()))$(if ($os.Major -lt 10) { '. Older Windows: some live tasks use newer cmdlets and will be reported as failed, the rest still run. Needs Windows PowerShell 5.1 (WMF 5.1).' })" }
    $r += [pscustomobject]@{ Check = 'Windows architecture'; Result = $(if ([Environment]::Is64BitOperatingSystem) { 'PASS' } else { 'WARN' }); Detail = $(if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit: the bundled Hayabusa, Chainsaw, YARA, Volatility and WinPmem builds are 64-bit. Put a 32-bit build in tools\ to use them.' }) }
    $r += [pscustomobject]@{ Check = 'CPU cores / memory'; Result = 'INFO'; Detail = "$([Environment]::ProcessorCount) cores; tools run at low priority and Hayabusa uses half of the cores" }
    $r += [pscustomobject]@{ Check = 'Language mode'; Result = $(if ($ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage') { 'PASS' } else { 'FAIL' }); Detail = $ExecutionContext.SessionState.LanguageMode }
    $r += [pscustomobject]@{ Check = 'Windows'; Result = $(if ($env:OS -eq 'Windows_NT') { 'PASS' } else { 'FAIL' }); Detail = [Environment]::OSVersion.VersionString }
    foreach ($d in 'app', 'tasks', 'config', 'tools') { $r += [pscustomobject]@{ Check = "folder $d"; Result = $(if (Test-Path (Join-Path $Root $d)) { 'PASS' } else { 'FAIL' }); Detail = (Join-Path $Root $d) } }
    $r += [pscustomobject]@{ Check = 'file config\tools.json'; Result = $(if (Test-Path (Join-Path $Root 'config\tools.json')) { 'PASS' } else { 'FAIL' }); Detail = '' }
    $w = 'FAIL'; $dt = ''; try { $tf = Join-Path $global:P.Output (".write_test_{0}.tmp" -f [guid]::NewGuid().ToString('N')); [IO.File]::WriteAllText($tf, 'x'); Remove-Item -LiteralPath $tf -Force; $w = 'PASS' } catch { $dt = $_.Exception.Message }
    $r += [pscustomobject]@{ Check = 'output folder is writable'; Result = $w; Detail = $dt }
    $r += [pscustomobject]@{ Check = 'Administrator'; Result = $(if (Test-As4Admin) { 'PASS' } else { 'WARN' }); Detail = 'Without it, Security log, Prefetch, memory capture and KAPE are skipped' }
    $free = Get-DiskFreeBytes $Root; $r += [pscustomobject]@{ Check = 'Free space on this drive'; Result = $(if ($free -gt 5GB) { 'PASS' } else { 'WARN' }); Detail = "$([math]::Round($free/1GB,1)) GB" }
    foreach ($t in Get-As4Tools) { $r += [pscustomobject]@{ Check = "tool: $($t.Name)"; Result = $(if ($t.Status -like 'PRESENT*') { 'PASS' } else { 'MISSING' }); Detail = $t.Status } }
    $rt = @(); foreach ($tl in (Get-As4Tools | Where-Object Path)) { $rt += @(Repair-As4ToolRuntimes -Folders @(Split-Path $tl.Path)) }; $rt = @($rt | Sort-Object Folder, Dll -Unique)
    $badRt = @($rt | Where-Object { -not $_.Ok }); $fixedRt = @($rt | Where-Object Ok)
    $r += [pscustomobject]@{ Check = 'Tool runtime libraries (Visual C++)'; Result = $(if ($badRt.Count) { 'WARN' } else { 'PASS' }); Detail = $(if ($badRt.Count) { "missing: $(($badRt | ForEach-Object { $_.Dll } | Select-Object -Unique) -join ', ')" } elseif ($fixedRt.Count) { "$($fixedRt.Count) file(s) copied from tools\_runtime next to the tools that need them" } else { 'every tool has what it needs' }) }
    $r
}

if ($Check) { Test-As4Environment | Format-Table -AutoSize | Out-String -Width 200 | Write-Host; exit 0 }

$bad = @(Test-As4Environment | Where-Object { $_.Result -eq 'FAIL' })
if ($bad.Count) { Write-Host 'Environment problems:' -ForegroundColor Red; $bad | Format-Table -AutoSize | Out-Host; if (-not $SelfTest) { Read-Host 'Press Enter to exit' | Out-Null; exit 3 } }

if ($Batch) {
    if (-not $CaseName) { Write-Host 'Batch mode needs -Case "name".' -ForegroundColor Red; exit 4 }
    try { Start-As4Case $CaseName | Out-Null } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 5 }
    $res = switch ($Batch) {
        'quick'  { Invoke-As4Batch -Tasks @(Get-As4QuickTasks | Where-Object Quick) -Label 'quick' }
        'full'   { Invoke-As4Batch -Tasks @(Get-As4QuickTasks) -Label 'full' }
        'triage' { Invoke-As4Batch -Tasks @(Get-As4TriageTasks) -Label 'triage' }
        'evtx'   { $c = Get-As4EvtxChannels | Where-Object { $_.Group -in 'Core', 'PowerShell' } | ForEach-Object { $_.Name }; Export-As4Evtx -Channels $c | Out-Null; @() }
        'hunt'    { $h = Invoke-LiveHunt -OnProgress { param($i, $n, $m) Write-Host "  [$i/$n] $m" -ForegroundColor Cyan }; if ($h.Verdict) { Write-Host "  Verdict: $($h.Verdict.Verdict) (score $($h.Verdict.Score))" -ForegroundColor Yellow; Write-Host "  Report: $($h.Files.Html)" }; @($h.Entry) }
        'package' { $k = New-As4EvidencePackage -Fast; Write-Host "  Package: $($k.Path)"; @() }
        default  { if (@(Get-As4Scenarios | Where-Object Id -eq $Batch).Count) { $sr = Invoke-As4Scenario -Id $Batch -OnProgress { param($i, $n, $m) Write-Host "  [$i/$n] $m" -ForegroundColor Cyan }; @($sr.Results) } else { Write-Host "Unknown batch '$Batch' (quick, full, triage, evtx, hunt, package, first5, malware, logons, ransomware, insider, persistence, full)" -ForegroundColor Red; exit 6 } }
    }
    Show-ResultTable $res
    $rep = New-As4Report $CaseName; Write-Host "Report: $($rep.Html)"
    exit $(if (@($res | Where-Object Status -eq 'FAILED').Count) { 1 } else { 0 })
}

if ($Cli) { Start-As4Cli; exit 0 }

# default: GUI (needs an STA thread)
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $a = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $MyInvocation.MyCommand.Path, '-Gui', '-Root', $Root)
    if ($SelfTest) { $a += '-SelfTest' }; if ($CaseName) { $a += @('-CaseName', $CaseName) }; if ($ScreenshotPath) { $a += @('-ScreenshotPath', $ScreenshotPath) }
    & powershell.exe @a
    exit $LASTEXITCODE
}
[Windows.Forms.Application]::EnableVisualStyles()
if ($SelfTest) { [void](Start-As4Case $(if ($CaseName) { $CaseName } else { 'SELFTEST' })) }
else {
    if ($CaseName) { [void](Start-As4Case $CaseName) }
    elseif (-not (Show-CaseDialog $null)) { exit 0 }
}
$form = Start-As4Gui
if ($SelfTest) {
    $form.Show(); [Windows.Forms.Application]::DoEvents()
    foreach ($pg in $global:G.Pages.Keys) {
        Show-Page $pg; [Windows.Forms.Application]::DoEvents()
        if ($ScreenshotPath) { $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height); $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height))); $bmp.Save((Join-Path $ScreenshotPath (($pg -replace '[^A-Za-z]', '') + '.png'))); $bmp.Dispose() }
    }
    Write-Host "GUI self-test OK: $($global:G.Pages.Count) pages"; $form.Close(); exit 0
}
[void]$form.ShowDialog()
