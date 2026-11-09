<#
 Builds the three launcher executables in the AS4 root with the C# compiler that ships with Windows (no SDK needed):
   AS4_IR_Tool.exe        GUI
   AS4_IR_Tool_Admin.exe  GUI, asks for administrator (UAC)
   AS4_IR_Tool_CLI.exe    console menus and unattended modes (passes its arguments on)
 The exes are small launchers: the tool itself stays in app\, tasks\, tools\ and config\ next to them.
 Optional: -SignThumbprint <cert> signs them with a code-signing certificate you own (recommended if your policy blocks unsigned files).
#>
param([string]$SignThumbprint)
$root = Split-Path -Parent $PSScriptRoot; $src = Join-Path $PSScriptRoot 'launcher'
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'; if (-not (Test-Path $csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'The .NET Framework C# compiler was not found.' }
Add-Type -AssemblyName System.Drawing

# icon: a pixel bird on a dark tile, saved as a PNG-compressed .ico (16..256)
$ico = Join-Path $src 'as4.ico'
$birdRows = @('.........XXXXXX.......', '.......XXXXXXXXXX.....', '......XXXXXXXXXeXXXXXX', '..X..XXXXXXXXXXXXX....', '.XXXXXXXXXXXXXXXXX....', 'XXXXXXXXXXXXXXXXX.....', '.XXXXXXXXXXXXXXXX.....', '...XXXXXXXXXXXXX......', '.....XXXXXXXXXX.......', '......XX...XX.........', '......XX...XX.........')
function New-Mark([int]$n) {
    $b = New-Object Drawing.Bitmap($n, $n); $g = [Drawing.Graphics]::FromImage($b); $g.Clear([Drawing.Color]::FromArgb(13, 18, 17))
    $g.PixelOffsetMode = 'Half'; $g.InterpolationMode = 'NearestNeighbor'
    $px = $n / 24.0; $ox = $n * 0.5 - 11 * $px; $oy = $n * 0.5 - 5.5 * $px
    $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(61, 220, 132)); $eye = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(13, 18, 17))
    for ($r = 0; $r -lt $birdRows.Count; $r++) { for ($c = 0; $c -lt $birdRows[$r].Length; $c++) { $ch = $birdRows[$r][$c]; if ($ch -eq 'X') { $g.FillRectangle($br, [single]($ox + $c * $px), [single]($oy + $r * $px), [single]($px + 0.5), [single]($px + 0.5)) } elseif ($ch -eq 'e') { $g.FillRectangle($eye, [single]($ox + $c * $px), [single]($oy + $r * $px), [single]($px + 0.5), [single]($px + 0.5)) } } }
    $g.Dispose(); $b }
$sizes = 16, 32, 48, 64, 128, 256; $pngs = @()
foreach ($s in $sizes) { $bm = New-Mark $s; $ms = New-Object IO.MemoryStream; $bm.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $pngs += , $ms.ToArray(); $bm.Dispose() }
$fs = [IO.File]::Create($ico); $bw = New-Object IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count); $off = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) { $s = $sizes[$i]; $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s })); $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s })); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$off); $off += $pngs[$i].Length }
foreach ($p in $pngs) { $bw.Write($p) }; $bw.Dispose(); $fs.Dispose()

function Build($name, $defs, $target, $manifest) {
    $out = Join-Path $root $name
    $a = @("/nologo", "/optimize+", "/platform:anycpu", "/target:$target", "/out:$out", "/win32icon:$ico", "/win32manifest:$(Join-Path $src $manifest)", "/reference:System.Windows.Forms.dll", "/reference:System.dll")
    if ($defs) { $a += "/define:$defs" }; $a += (Join-Path $src 'Launcher.cs')
    $o = & $csc @a 2>&1; if ($LASTEXITCODE -ne 0) { throw "Build of $name failed:`n$($o -join "`n")" }
    if ($SignThumbprint) { $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My | Where-Object Thumbprint -eq $SignThumbprint | Select-Object -First 1; if (-not $cert) { throw "Certificate $SignThumbprint not found" }; [void](Set-AuthenticodeSignature -FilePath $out -Certificate $cert -TimestampServer $null -ErrorAction Stop) }
    "{0,-26} {1,8:N0} bytes" -f $name, (Get-Item $out).Length
}
Build 'AS4_IR_Tool.exe'       ''    'winexe' 'as4_user.manifest'
Build 'AS4_IR_Tool_Admin.exe' ''    'winexe' 'as4_admin.manifest'
Build 'AS4_IR_Tool_CLI.exe'   'CLI' 'exe'    'as4_user.manifest'
