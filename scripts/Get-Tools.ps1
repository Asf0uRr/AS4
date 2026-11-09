<#
 AS4 - fetch bundled tools from their official sources. Run this on the ANALYST WORKSTATION only (never on an endpoint).
   .\Get-Tools.ps1                      download anything missing, verify, extract into tools\, record hashes
   .\Get-Tools.ps1 -DownloadDir D:\dl   use already-downloaded archives from that folder (no network)
   .\Get-Tools.ps1 -NoSymbols           skip the 800 MB Volatility Windows symbol pack
Tools that need a registration form (KAPE, FTK Imager) cannot be fetched here: download them yourself and use Prepare-Tools.ps1 -Register.
#>
param([string]$DownloadDir, [switch]$NoSymbols, [switch]$Force)
if ($env:AS4_TARGET_MODE -eq '1') { Write-Host 'Refusing to run: target-endpoint mode is active. Prepare tools on the analyst workstation.' -ForegroundColor Red; exit 9 }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'app\Core.ps1'); Initialize-As4 -Root $root
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not $DownloadDir) { $DownloadDir = Join-Path ([IO.Path]::GetTempPath()) 'as4_downloads'; New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null }

$items = @(
    @{ Id = 'winpmem';     Folder = 'MemoryAcquisition'; Url = 'https://github.com/Velocidex/WinPmem/releases/download/v4.0.rc1/winpmem_mini_x64_rc2.exe'; File = 'winpmem_mini_x64_rc2.exe'; Main = 'winpmem_mini_x64_rc2.exe'; Version = '4.0 rc2 (mini, x64)'; Zip = $false }
    @{ Id = 'winpmem-go';  Folder = 'MemoryAcquisition'; Url = 'https://github.com/Velocidex/WinPmem/releases/download/v4.0.rc1/go-winpmem_amd64_1.0-rc2_signed.exe'; File = 'go-winpmem_amd64_1.0-rc2_signed.exe'; Main = 'go-winpmem_amd64_1.0-rc2_signed.exe'; Version = 'go-winpmem 1.0 rc2'; Zip = $false }
    @{ Id = 'yara';        Folder = 'YARA'; Url = 'https://github.com/VirusTotal/yara/releases/download/v4.5.5/yara-4.5.5-2368-win64.zip'; File = 'yara-4.5.5-2368-win64.zip'; Main = 'yara64.exe'; Version = '4.5.5'; Zip = $true }
    @{ Id = 'volatility3'; Folder = 'Volatility3'; Url = 'https://github.com/volatilityfoundation/volatility3/releases/download/v2.28.2/volatility3-win-exes-2.28.2.zip'; File = 'volatility3-win-exes-2.28.2.zip'; Main = 'vol.exe'; Version = '2.28.2'; Zip = $true }
    @{ Id = 'autorunsc';   Folder = 'Sysinternals'; Url = 'https://download.sysinternals.com/files/Autoruns.zip'; File = 'Autoruns.zip'; Main = 'autorunsc64.exe'; Version = ''; Zip = $true }
    @{ Id = 'sigcheck';    Folder = 'Sysinternals'; Url = 'https://download.sysinternals.com/files/Sigcheck.zip'; File = 'Sigcheck.zip'; Main = 'sigcheck64.exe'; Version = ''; Zip = $true }
    @{ Id = 'handle';      Folder = 'Sysinternals'; Url = 'https://download.sysinternals.com/files/Handle.zip'; File = 'Handle.zip'; Main = 'handle64.exe'; Version = ''; Zip = $true }
    @{ Id = 'listdlls';    Folder = 'Sysinternals'; Url = 'https://download.sysinternals.com/files/ListDlls.zip'; File = 'ListDlls.zip'; Main = 'Listdlls64.exe'; Version = ''; Zip = $true }
    @{ Id = 'pstools';     Folder = 'Sysinternals'; Url = 'https://download.sysinternals.com/files/PSTools.zip'; File = 'PSTools.zip'; Main = 'pslist64.exe'; Version = ''; Zip = $true }
    @{ Id = 'tcpview';     Folder = 'Sysinternals'; Url = 'https://download.sysinternals.com/files/TCPView.zip'; File = 'TCPView.zip'; Main = 'tcpvcon64.exe'; Version = ''; Zip = $true }
    @{ Id = 'strings';     Folder = 'Sysinternals'; Url = 'https://download.sysinternals.com/files/Strings.zip'; File = 'Strings.zip'; Main = 'strings64.exe'; Version = ''; Zip = $true }
)
if (-not $NoSymbols) { $items += @{ Id = 'vol3-symbols'; Folder = 'Volatility3\symbols'; Url = 'https://downloads.volatilityfoundation.org/volatility3/symbols/windows.zip'; File = 'vol3_symbols_windows.zip'; Main = $null; Version = 'Windows symbol pack'; Zip = $false; Rename = 'windows.zip' } }

$mf = Join-Path $root 'config\tools_manifest.json'
$man = @(); if (Test-Path $mf) { $o = Get-Content $mf -Raw | ConvertFrom-Json; $man = @(foreach ($x in $o) { $x }) }
function Save-Man { ($man | ConvertTo-Json -Depth 5) | Set-Content $mf -Encoding UTF8 }

foreach ($it in $items) {
    $arc = Join-Path $DownloadDir $it.File
    $destDir = Join-Path $root "tools\$($it.Folder)"
    if (-not $Force -and $it.Main -and (Get-ChildItem $destDir -Recurse -Filter $it.Main -ErrorAction SilentlyContinue | Select-Object -First 1)) { Write-Host "present   $($it.Id)"; continue }
    if (-not (Test-Path -LiteralPath $arc)) { Write-Host "download  $($it.Id)  $($it.Url)"; & curl.exe -L --fail --silent --show-error --retry 3 -o $arc $it.Url; if ($LASTEXITCODE -ne 0) { Write-Host "FAILED    $($it.Id)" -ForegroundColor Red; if (Test-Path $arc) { Remove-Item $arc }; continue } }
    $ah = Get-As4Sha256 $arc
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    if ($it.Zip) {
        try { $z = [IO.Compression.ZipFile]::OpenRead($arc); foreach ($e in $z.Entries) { if ($e.FullName.EndsWith('/')) { continue }; $d = Join-Path $destDir $e.FullName; New-Item -ItemType Directory -Path (Split-Path $d) -Force | Out-Null; [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $d, $true) }; $z.Dispose() }
        catch { Write-Host "BAD ARCHIVE $($it.Id): $($_.Exception.Message)" -ForegroundColor Red; continue }
    } else { $dn = if ($it.Rename) { $it.Rename } else { $it.File }; Copy-Item -LiteralPath $arc -Destination (Join-Path $destDir $dn) -Force }
    $mainPath = $null; if ($it.Main) { $mainPath = (Get-ChildItem $destDir -Recurse -Filter $it.Main | Select-Object -First 1).FullName }
    $target = if ($mainPath) { $mainPath } else { Join-Path $destDir $(if ($it.Rename) { $it.Rename } else { $it.File }) }
    $sig = $null; if ($target -like '*.exe') { $sig = Get-AuthenticodeSignature -LiteralPath $target }
    $man = @($man | Where-Object { $_.Id -ne $it.Id })
    $man += [ordered]@{ Id = $it.Id; File = $target.Substring($root.Length).TrimStart('\'); Sha256 = (Get-As4Sha256 $target); Version = $it.Version; Signature = $(if ($sig) { "$($sig.Status)" } else { 'n/a' }); Signer = $(if ($sig) { $sig.SignerCertificate.Subject } else { '' })
        OfficialSource = $it.Url; Archive = $it.File; ArchiveSha256 = $ah; RecordedUtc = (Get-UtcIso); Provenance = 'Downloaded from the official URL; vendor checksum not compared (none published for this asset)' }
    Save-Man
    Write-Host ("installed {0,-13} signature={1}" -f $it.Id, $(if ($sig) { $sig.Status } else { 'n/a' }))
}
Write-Host 'Done. KAPE and FTK Imager need a registration form: download them from the vendor, then run Prepare-Tools.ps1 -Register.'
