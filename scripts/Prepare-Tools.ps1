<#
 AS4 - Analyst Workstation Preparation (NOT for target endpoints).
 This script never downloads anything. You obtain tools yourself from the official source, then register/validate them here.
   .\Prepare-Tools.ps1 -List                              inventory + official sources + licence notes
   .\Prepare-Tools.ps1 -OpenSourcePage -Tool kape         open the official page in your browser
   .\Prepare-Tools.ps1 -Register -Tool yara -File C:\dl\yara64.exe [-ExpectedSha256 <vendor hash>] [-Copy]
        validates the file (hash, Authenticode, optional vendor hash), optionally copies it into tools\<folder>, records it in config\tools_manifest.json
   .\Prepare-Tools.ps1 -Verify                            re-hash every registered tool and report mismatches
#>
param([switch]$List, [switch]$Register, [switch]$Verify, [switch]$OpenSourcePage, [string]$Tool, [string]$File, [string]$ExpectedSha256, [switch]$Copy, [string]$Version)
if ($env:AS4_TARGET_MODE -eq '1') { Write-Host 'Refusing to run: AS4 target-endpoint mode is active. Prepare tools on the analyst workstation.' -ForegroundColor Red; exit 9 }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'app\Core.ps1'); Initialize-As4 -Root $root
$cfg = Get-Content (Join-Path $root 'config\tools.json') -Raw | ConvertFrom-Json
$mf = Join-Path $root 'config\tools_manifest.json'
function Load-Manifest { if (Test-Path $mf) { $o = Get-Content $mf -Raw | ConvertFrom-Json; foreach ($x in $o) { $x } } }
function Save-Manifest($m) { ($m | ConvertTo-Json -Depth 5) | Set-Content $mf -Encoding UTF8 }
if ($List -or (-not ($Register -or $Verify -or $OpenSourcePage))) {
    Get-As4Tools | Format-Table Name, Status, FileVersion, License, Redistribution -AutoSize -Wrap
    Write-Host 'Sources:'; foreach ($t in $cfg) { Write-Host ("  {0,-12} {1}" -f $t.Id, $t.Source) }
    Write-Host "`nChecklist: (1) download from the official source above; (2) compare against the vendor-published hash if provided; (3) read the licence - do not bundle if redistribution is restricted (use the integration point and have each analyst obtain it); (4) -Register the file."
    return
}
if ($OpenSourcePage) { $t = $cfg | Where-Object Id -eq $Tool; if (-not $t) { throw "Unknown tool id '$Tool'" }; Start-Process $t.Source; return }
if ($Verify) {
    foreach ($m in Load-Manifest) { $p = Join-Path $root $m.File; if (-not (Test-Path -LiteralPath $p)) { Write-Host "MISSING   $($m.Id) $($m.File)" -ForegroundColor Yellow; continue }
        $h = Get-As4Sha256 $p; if ($h -eq $m.Sha256) { Write-Host "VERIFIED  $($m.Id)" -ForegroundColor Green } else { Write-Host "MISMATCH  $($m.Id)" -ForegroundColor Red } }
    return
}
if ($Register) {
    $t = $cfg | Where-Object Id -eq $Tool; if (-not $t) { throw "Unknown tool id '$Tool' (see -List)" }
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "File not found: $File" }
    $h = Get-As4Sha256 $File
    if ($ExpectedSha256 -and $h -ne $ExpectedSha256.ToLower()) { throw "SHA-256 mismatch. Expected $ExpectedSha256 but file is $h. NOT registering." }
    $sig = $null; try { $sig = Get-AuthenticodeSignature -LiteralPath $File } catch {}
    Write-Host "SHA-256: $h"; Write-Host "Authenticode: $($sig.Status) $($sig.SignerCertificate.Subject)"
    if ($sig -and $sig.Status -ne 'Valid') { Write-Host 'WARNING: file is not validly signed - verify provenance by other means (vendor hash).' -ForegroundColor Yellow }
    Write-Host "Licence: $($t.License)`nRedistribution: $($t.Redistribution)" -ForegroundColor Cyan
    $dest = $File
    if ($Copy) { $dir = Join-Path $root "tools\$($t.Folder)"; New-Item -ItemType Directory -Path $dir -Force | Out-Null; $dest = Join-Path $dir (Split-Path $File -Leaf); if (Test-Path $dest) { throw "Destination exists, not overwriting: $dest" }; Copy-Item -LiteralPath $File -Destination $dest }
    if (-not $dest.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Registered file must be inside the AS4 folder (use -Copy).' }
    $m = @(Load-Manifest | Where-Object Id -ne $Tool)
    $m += [ordered]@{ Id = $Tool; Name = $t.Name; File = $dest.Substring($root.Length).TrimStart('\'); Sha256 = $h; Version = $Version; Signature = "$($sig.Status)"; Signer = $sig.SignerCertificate.Subject; VendorHashChecked = [bool]$ExpectedSha256; OfficialSource = $t.Source; License = $t.License; RecordedUtc = (Get-UtcIso); Provenance = $(if ($ExpectedSha256) { 'SHA-256 matched vendor-published value' } else { 'Hash recorded locally; vendor hash NOT compared' }) }
    Save-Manifest $m; Write-Host "Registered $Tool." -ForegroundColor Green
}
