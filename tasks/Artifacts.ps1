# AS4 IR Tool - Artifacts

# ================= ARTIFACT CATALOG =================
function Get-As4ArtifactCatalog {
    $U = 'C:\Users\*'
    @(
    @{ Id='reghives'; Name='Registry hives (SYSTEM, SOFTWARE, SAM, SECURITY)'; Admin='required'; Sensitive=$true; Live=$true
       What='Offline copies of core machine hives via reg save, plus hive transaction logs where readable.'
       Why='Source for shimcache, services, installed software, USB history, local account metadata.'; Value='Very high'
       Note='SAM/SECURITY contain credential material. AS4 only copies them; it never parses or extracts credentials.'
       RegSave=@(@{Key='HKLM\SYSTEM';Name='SYSTEM'},@{Key='HKLM\SOFTWARE';Name='SOFTWARE'},@{Key='HKLM\SAM';Name='SAM'},@{Key='HKLM\SECURITY';Name='SECURITY'})
       Files=@('C:\Windows\System32\config\*.LOG1','C:\Windows\System32\config\*.LOG2','C:\Windows\System32\config\RegBack\*') }
    @{ Id='userhives'; Name='User registry hives (NTUSER.DAT, UsrClass.dat)'; Admin='partial'; Sensitive=$true; Live=$true
       What='Per-user hives. Hives of logged-on users are locked; AS4 tries shared-read and records failures. Current user is also saved with reg save HKCU.'
       Why='UserAssist, RunMRU, ShellBags, RDP history, MRU lists.'; Value='Very high'
       Note='For locked hives use KAPE or FTK Imager (raw read) - AS4 does not use raw disk access itself.'
       RegSave=@(@{Key='HKCU';Name='HKCU_current_user'})
       Files=@("$U\NTUSER.DAT","$U\NTUSER.DAT.LOG1","$U\NTUSER.DAT.LOG2","$U\AppData\Local\Microsoft\Windows\UsrClass.dat","$U\AppData\Local\Microsoft\Windows\UsrClass.dat.LOG1","$U\AppData\Local\Microsoft\Windows\UsrClass.dat.LOG2") }
    @{ Id='shimcache'; Name='Shimcache (AppCompatCache) key export'; Admin='none'; Sensitive=$false; Live=$true
       What='reg export of the AppCompatCache key (binary blob).'; Why='Evidence of executable presence/execution on disk. Parse offline (e.g. Chainsaw analyse shimcache needs the SYSTEM hive).'; Value='High'
       RegExport=@(@{Key='HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache';Name='AppCompatCache'}) }
    @{ Id='amcache'; Name='Amcache'; Admin='required'; Sensitive=$false; Live=$true
       What='Amcache.hve and logs (locked by OS; shared-read attempted).'; Why='Execution/installation evidence incl. SHA-1 of binaries.'; Value='High'
       Files=@('C:\Windows\appcompat\Programs\Amcache.hve','C:\Windows\appcompat\Programs\Amcache.hve.LOG1','C:\Windows\appcompat\Programs\Amcache.hve.LOG2','C:\Windows\appcompat\Programs\RecentFileCache.bcf') }
    @{ Id='prefetch'; Name='Prefetch'; Admin='required'; Sensitive=$false; Live=$true
       What='*.pf files from C:\Windows\Prefetch.'; Why='Program execution counts, last 8 run times, referenced files.'; Value='High'
       Files=@('C:\Windows\Prefetch\*.pf','C:\Windows\Prefetch\Layout.ini') }
    @{ Id='evtxfiles'; Name='Event log files (file copy)'; Admin='partial'; Sensitive=$true; Live=$true
       What='Raw *.evtx from winevt\Logs by file copy. Prefer the Event Logs module (wevtutil) for a consistent export.'; Why='Full logs for Chainsaw and timeline.'; Value='Very high'
       Files=@('C:\Windows\System32\winevt\Logs\*.evtx') }
    @{ Id='powershell'; Name='PowerShell history and transcripts'; Admin='none'; Sensitive=$true; Live=$true
       What='PSReadLine ConsoleHost_history.txt and transcript files in user Documents.'; Why='Interactive command history.'; Value='High'
       Files=@("$U\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\*.txt","$U\Documents\PowerShell_transcript*.txt") }
    @{ Id='tasks'; Name='Scheduled task files'; Admin='partial'; Sensitive=$false; Live=$true
       What='XML task definitions in C:\Windows\System32\Tasks and legacy .job files.'; Why='Persistence and execution.'; Value='High'
       Files=@('C:\Windows\System32\Tasks\*|r','C:\Windows\Tasks\*.job') }
    @{ Id='services'; Name='Services and startup configuration'; Admin='none'; Sensitive=$false; Live=$true
       What='reg export of Services and Run/RunOnce keys.'; Why='Service and autostart persistence.'; Value='High'
       RegExport=@(@{Key='HKLM\SYSTEM\CurrentControlSet\Services';Name='Services'},@{Key='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';Name='HKLM_Run'},@{Key='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';Name='HKLM_RunOnce'},@{Key='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';Name='HKCU_Run'},@{Key='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';Name='HKCU_RunOnce'}) }
    @{ Id='lnkjump'; Name='LNK files and Jump Lists'; Admin='partial'; Sensitive=$true; Live=$true
       What='Recent shortcuts, AutomaticDestinations and CustomDestinations.'; Why='File/folder access evidence, even for deleted/removable files.'; Value='High'
       Files=@("$U\AppData\Roaming\Microsoft\Windows\Recent\*|r") }
    @{ Id='recycle'; Name='Recycle Bin metadata ($I files)'; Admin='required'; Sensitive=$true; Live=$true
       What='$I metadata files only (original path, size, deletion time); $R content files are not copied.'; Why='Deleted-file evidence.'; Value='Medium'
       Files=@('C:\$Recycle.Bin\*\$I*') }
    @{ Id='browser'; Name='Browser history and downloads'; Admin='none'; Sensitive=$true; Live=$true
       What='Chrome/Edge History and Bookmarks, Firefox places.sqlite. Logins, cookies and form data are deliberately NOT collected.'; Why='Web activity, download sources.'; Value='Medium-High'
       Note='Only collect where authorised; contains personal browsing data. Databases may be locked while the browser runs.'
       Files=@("$U\AppData\Local\Google\Chrome\User Data\*\History","$U\AppData\Local\Google\Chrome\User Data\*\Bookmarks","$U\AppData\Local\Microsoft\Edge\User Data\*\History","$U\AppData\Local\Microsoft\Edge\User Data\*\Bookmarks","$U\AppData\Roaming\Mozilla\Firefox\Profiles\*\places.sqlite") }
    @{ Id='useractivity'; Name='User activity (Windows Timeline, Office recent)'; Admin='none'; Sensitive=$true; Live=$true
       What='ActivitiesCache.db and Office recent file lists.'; Why='Application/document activity timeline.'; Value='Medium'
       Files=@("$U\AppData\Local\ConnectedDevicesPlatform\*\ActivitiesCache.db","$U\AppData\Roaming\Microsoft\Office\Recent\*") }
    @{ Id='defender'; Name='Windows Defender history and logs'; Admin='required'; Sensitive=$false; Live=$true
       What='MPLog support logs and DetectionHistory. Quarantined sample contents are not collected.'; Why='Detections, scan history, exclusions context.'; Value='High'
       Files=@('C:\ProgramData\Microsoft\Windows Defender\Support\*.log','C:\ProgramData\Microsoft\Windows Defender\Scans\History\Service\*|r') }
    @{ Id='srum'; Name='SRUM database'; Admin='required'; Sensitive=$false; Live=$true
       What='SRUDB.dat (locked; shared-read attempted) and SRU logs, plus SRUM registry export.'; Why='Per-app network bytes and execution over ~30-60 days. Chainsaw can analyse it with the SOFTWARE hive.'; Value='High'
       Files=@('C:\Windows\System32\sru\*'); RegExport=@(@{Key='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SRUM';Name='SRUM_reg'}) }
    @{ Id='wmi'; Name='WMI repository'; Admin='required'; Sensitive=$false; Live=$true
       What='OBJECTS.DATA, INDEX.BTR, MAPPING*.MAP.'; Why='WMI persistence (subscriptions) analysis offline.'; Value='Medium-High'
       Files=@('C:\Windows\System32\wbem\Repository\*') }
    @{ Id='wer'; Name='Windows Error Reporting / crash artifacts'; Admin='partial'; Sensitive=$false; Live=$true
       What='Report.wer files (no memory dumps).'; Why='Crash evidence of exploited or unstable binaries.'; Value='Low-Medium'
       Files=@('C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*\Report.wer','C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*\Report.wer',"$U\AppData\Local\Microsoft\Windows\WER\ReportArchive\*\Report.wer") }
    @{ Id='temp'; Name='Temp / suspicious location inventory (metadata only)'; Admin='partial'; Sensitive=$false; Live=$true
       What='Inventory (name, size, times, SHA-256) of files in Temp, Public, ProgramData and Downloads. Files are NOT copied.'; Why='Find dropped payloads without bulk copying.'; Value='Medium'
       Inventory=@('C:\Windows\Temp',"$U\AppData\Local\Temp",'C:\Users\Public','C:\ProgramData',"$U\Downloads") }
    @{ Id='netcfg'; Name='Hosts file, DNS and firewall configuration'; Admin='partial'; Sensitive=$false; Live=$true
       What='hosts/lmhosts, firewall log files, firewall policy registry export.'; Why='Name-resolution tampering, firewall changes.'; Value='Medium'
       Files=@('C:\Windows\System32\drivers\etc\*','C:\Windows\System32\LogFiles\Firewall\*.log'); RegExport=@(@{Key='HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy';Name='FirewallPolicy'}) }
    @{ Id='weblogs'; Name='IIS / HTTP logs'; Admin='partial'; Sensitive=$true; Live=$true
       What='IIS logs and HTTPERR logs when present.'; Why='Web-server compromise.'; Value='Situational'
       Files=@('C:\inetpub\logs\LogFiles\*|r','C:\Windows\System32\LogFiles\HTTPERR\*.log') }
    @{ Id='rdp'; Name='RDP client/server artifacts'; Admin='none'; Sensitive=$true; Live=$true
       What='Terminal Server Client registry, Default.rdp, bitmap cache, server settings export.'; Why='Outbound RDP history and cached screens.'; Value='High'
       Files=@("$U\Documents\Default.rdp","$U\AppData\Local\Microsoft\Terminal Server Client\Cache\*")
       RegExport=@(@{Key='HKCU\SOFTWARE\Microsoft\Terminal Server Client';Name='RDPClient_HKCU'},@{Key='HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server';Name='TerminalServer_config'}) }
    @{ Id='ntfs'; Name='NTFS metadata ($MFT, $LogFile, $UsnJrnl)'; Admin='required'; Sensitive=$false; Live=$false
       What='These need raw volume access. AS4 does NOT copy them natively. It records fsutil NTFS info and a parsed USN journal export (fsutil usn readjournal, not the raw $J).'
       Why='File system timeline, deleted-file evidence.'; Value='Very high'
       Note='For raw $MFT/$LogFile/$J use KAPE (!SANS_Triage / $MFT targets) or FTK Imager, or acquire a forensic image.'
       Native=@(@{Exe='fsutil.exe';Args=@('fsinfo','ntfsinfo','C:');Name='ntfsinfo';Ext='txt'},@{Exe='fsutil.exe';Args=@('usn','queryjournal','C:');Name='usn_queryjournal';Ext='txt'},@{Exe='fsutil.exe';Args=@('usn','readjournal','C:','csv');Name='usn_readjournal_parsed';Ext='csv';Timeout=900})
       RawOnly=@('$MFT','$LogFile','$UsnJrnl:$J') }
    )
}

function Copy-As4FileSafe {
    param([string]$Src, [string]$Dst)
    $d = Split-Path $Dst; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $si = Get-Item -LiteralPath $Src -Force
    try { [IO.File]::Copy($Src, $Dst, $false) }
    catch [IO.IOException] {
        if (Test-Path -LiteralPath $Dst) { Remove-Item -LiteralPath $Dst -Force -ErrorAction SilentlyContinue }
        $in = New-Object IO.FileStream($Src, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { $out = New-Object IO.FileStream($Dst, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write); try { $in.CopyTo($out) } finally { $out.Dispose() } } finally { $in.Dispose() }
    }
    try { $di = Get-Item -LiteralPath $Dst -Force; $di.CreationTimeUtc = $si.CreationTimeUtc; $di.LastWriteTimeUtc = $si.LastWriteTimeUtc; $di.LastAccessTimeUtc = $si.LastAccessTimeUtc } catch {}
}

function Get-As4FilesFromSpec {
    param([string[]]$Specs, $Since, [string[]]$Extensions, [double]$MaxMB = 0, [ref]$Errors)
    foreach ($s in $Specs) {
        $rec = $false; $p = $s; if ($s.EndsWith('|r')) { $rec = $true; $p = $s.Substring(0, $s.Length - 2) }
        $ev = @()
        $items = @()
        if ($rec) {
            $base = $p; if ($base.EndsWith('\*')) { $base = $base.Substring(0, $base.Length - 2) }
            $items = Get-ChildItem -Path $base -Recurse -Force -File -ErrorAction SilentlyContinue -ErrorVariable +ev
        } else { $items = Get-ChildItem -Path $p -Force -File -ErrorAction SilentlyContinue -ErrorVariable +ev }
        foreach ($e in $ev) { if ($Errors) { $Errors.Value += [pscustomobject]@{ Spec = $s; Error = $e.Exception.Message } } }
        foreach ($f in $items) {
            if ($Since -and $f.LastWriteTime -lt $Since -and $f.CreationTime -lt $Since) { continue }
            if ($Extensions -and $Extensions.Count -and ($Extensions -notcontains $f.Extension.TrimStart('.').ToLower())) { continue }
            if ($MaxMB -gt 0 -and $f.Length -gt ($MaxMB * 1MB)) { continue }
            $f
        }
    }
}

function Convert-ToDestRel { param([string]$Full) ($Full -replace '^([A-Za-z]):', '$1') -replace '^\\\\', 'UNC\' }

function Invoke-As4ArtifactCategory {
    param($Cat, $Since, [string[]]$Extensions, [double]$MaxMB = 0, [switch]$Duplicates, [string]$Dest)
    $e = New-As4Entry ('artifact:' + $Cat.Id) $Cat.Name $global:CaseFolders.Art
    $e.Notes = @(); $e.Warnings = @(); $outFiles = @(); $rows = @()
    $isAdmin = Test-As4Admin
    $root = if ($Dest) { $Dest } else { Join-Path (Get-CaseFolder 'Art') $Cat.Id }
    try {
        if ($Cat.Admin -eq 'required' -and -not $isAdmin) { $e.Status = 'SKIPPED'; $e.Notes += 'Requires administrator.'; return (Complete-As4Entry $e @()) }
        if ($Cat.Admin -eq 'partial' -and -not $isAdmin) { $e.Warnings += 'Not elevated: some files or other users'' profiles will be inaccessible.' }
        $e.Command = 'AS4 artifact collector'; $e.Arguments = ($Cat.Id + $(if ($Since) { " since=$Since" }) + $(if ($Extensions) { " ext=$($Extensions -join ',')" }) + $(if ($MaxMB) { " maxMB=$MaxMB" }))
        $ok = 0; $bad = 0
        foreach ($rs in @($Cat.RegSave)) {
            if (-not $rs) { continue }
            if ($global:Cancel) { break }
            $dest = Get-UniquePath (Join-Path $root 'registry') $rs.Name 'hiv'
            $r = Invoke-As4Native -Exe 'reg.exe' -Arguments @('save', $rs.Key, $dest) -TimeoutSec 300
            if ($r.ExitCode -eq 0 -and (Test-Path -LiteralPath $dest)) { $ok++; $outFiles += $dest; $rows += [pscustomobject]@{ Source = $rs.Key; Dest = (Get-RelPath $dest); Status = 'COPIED'; Error = '' } }
            else { $bad++; $rows += [pscustomobject]@{ Source = $rs.Key; Dest = ''; Status = 'FAILED'; Error = ($r.StdErr.Trim() + ' ' + $r.Error).Trim() }; if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue } }
        }
        foreach ($rx in @($Cat.RegExport)) {
            if (-not $rx) { continue }
            if ($global:Cancel) { break }
            $dest = Get-UniquePath (Join-Path $root 'registry_export') $rx.Name 'reg'
            $r = Invoke-As4Native -Exe 'reg.exe' -Arguments @('export', $rx.Key, $dest) -TimeoutSec 300
            if ($r.ExitCode -eq 0 -and (Test-Path -LiteralPath $dest)) { $ok++; $outFiles += $dest; $rows += [pscustomobject]@{ Source = $rx.Key; Dest = (Get-RelPath $dest); Status = 'COPIED'; Error = '' } }
            else { $bad++; $rows += [pscustomobject]@{ Source = $rx.Key; Dest = ''; Status = 'FAILED'; Error = ($r.StdErr.Trim() + ' ' + $r.Error).Trim() }; if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue } }
        }
        foreach ($nv in @($Cat.Native)) {
            if (-not $nv) { continue }
            if ($global:Cancel) { break }
            $to = if ($nv.Timeout) { $nv.Timeout } else { 180 }
            $r = Invoke-As4Native -Exe $nv.Exe -Arguments $nv.Args -TimeoutSec $to
            $dest = Get-UniquePath $root $nv.Name $nv.Ext
            if ($r.ExitCode -eq 0 -and $r.StdOut.Trim()) { Write-As4File $dest $r.StdOut; $ok++; $outFiles += $dest; $rows += [pscustomobject]@{ Source = "$($nv.Exe) $($r.ArgString)"; Dest = (Get-RelPath $dest); Status = 'COPIED'; Error = '' } }
            else { $bad++; $rows += [pscustomobject]@{ Source = "$($nv.Exe) $($r.ArgString)"; Dest = ''; Status = 'FAILED'; Error = ("exit=$($r.ExitCode) $($r.StdErr.Trim()) $($r.Error)").Trim() } }
        }
        foreach ($raw in @($Cat.RawOnly)) { if ($raw) { $rows += [pscustomobject]@{ Source = $raw; Dest = ''; Status = 'NOT_COLLECTED'; Error = 'Requires raw volume access; use KAPE or FTK Imager.' } } }
        if ($Cat.Files) {
            $errs = @(); $files = @(Get-As4FilesFromSpec -Specs $Cat.Files -Since $Since -Extensions $Extensions -MaxMB $MaxMB -Errors ([ref]$errs))
            $total = ($files | Measure-Object Length -Sum).Sum
            $free = Get-DiskFreeBytes $root
            if ($free -and $total -and $total * 1.1 -gt $free) { $e.Warnings += 'Insufficient free space for this category.'; throw "Need ~$([math]::Round($total/1MB)) MB, only $([math]::Round($free/1MB)) MB free at destination." }
            foreach ($f in $files) {
                if ($global:Cancel) { break }
                $dst = Join-Path $root (Convert-ToDestRel $f.FullName)
                try {
                    if (Test-Path -LiteralPath $dst) { throw 'destination exists (not overwritten)' }
                    Copy-As4FileSafe $f.FullName $dst
                    $ok++; $outFiles += $dst
                    $rows += [pscustomobject]@{ Source = $f.FullName; Dest = (Get-RelPath $dst); Status = 'COPIED'; Error = ''; Size = $f.Length; CreatedUtc = $f.CreationTimeUtc.ToString('o'); ModifiedUtc = $f.LastWriteTimeUtc.ToString('o'); AccessedUtc = $f.LastAccessTimeUtc.ToString('o') }
                } catch { $bad++; $rows += [pscustomobject]@{ Source = $f.FullName; Dest = ''; Status = 'FAILED'; Error = $_.Exception.Message; Size = $f.Length; CreatedUtc = $f.CreationTimeUtc.ToString('o'); ModifiedUtc = $f.LastWriteTimeUtc.ToString('o'); AccessedUtc = $f.LastAccessTimeUtc.ToString('o') } }
            }
            foreach ($er in $errs) { $rows += [pscustomobject]@{ Source = $er.Spec; Dest = ''; Status = 'INACCESSIBLE'; Error = $er.Error } }
            if (-not $files.Count -and -not $errs.Count) { $rows += [pscustomobject]@{ Source = ($Cat.Files -join '; '); Dest = ''; Status = 'NOT_FOUND'; Error = 'No matching files.' } }
        }
        if ($Cat.Inventory) {
            $files = @(Get-As4FilesFromSpec -Specs ($Cat.Inventory | ForEach-Object { $_ + '|r' }) -Since $Since -Extensions $Extensions -MaxMB $MaxMB)
            foreach ($f in $files) { if ($global:Cancel) { break }; $h = $null; try { $h = Get-As4Sha256 $f.FullName } catch {}; $rows += [pscustomobject]@{ Source = $f.FullName; Dest = ''; Status = 'INVENTORIED'; Error = ''; Size = $f.Length; CreatedUtc = $f.CreationTimeUtc.ToString('o'); ModifiedUtc = $f.LastWriteTimeUtc.ToString('o'); AccessedUtc = $f.LastAccessTimeUtc.ToString('o'); SourceSha256 = $h }; $ok++ }
        }
        if ($rows.Count) {
            $inv = Get-UniquePath $root '_inventory' 'csv'
            $rows | Export-Csv -LiteralPath $inv -NoTypeInformation -Encoding UTF8; $outFiles += $inv
            if ($Duplicates) {
                $hs = @(); foreach ($d in ($rows | Where-Object { $_.Status -eq 'COPIED' -and $_.Dest })) { $p = Join-Path $global:Case.Dir $d.Dest; if (Test-Path -LiteralPath $p -PathType Leaf) { $hs += [pscustomobject]@{ Sha256 = (Get-As4Sha256 $p); Path = $d.Dest } } }
                $dups = $hs | Group-Object Sha256 | Where-Object Count -gt 1 | ForEach-Object { $g = $_; $g.Group | ForEach-Object { [pscustomobject]@{ Sha256 = $g.Name; Path = $_.Path } } }
                if ($dups) { $df = Get-UniquePath $root '_duplicates' 'csv'; $dups | Export-Csv -LiteralPath $df -NoTypeInformation; $outFiles += $df }
            }
        }
        $e.Notes += "$ok item(s) collected, $bad failed. Timestamps of copies are set from the source; originals are listed in _inventory.csv. Source last-access time may change on some systems."
        if ($global:Cancel) { $e.Status = 'CANCELLED'; $e.Notes += 'Cancelled; completed files remain valid.' }
        elseif ($ok -eq 0 -and $bad -gt 0) { $e.Status = 'FAILED' }
        elseif ($ok -eq 0) { $e.Status = 'OK'; $e.Notes += 'Nothing present on this system.' }
        else { $e.Status = 'OK'; if ($bad) { $e.Warnings += "$bad item(s) not collected (see inventory)." } }
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    Complete-As4Entry $e $outFiles
}

function Invoke-As4Artifacts {
    param([string[]]$Ids, $Since, [string[]]$Extensions, [double]$MaxMB = 0, [switch]$Duplicates, [scriptblock]$OnProgress)
    Start-As4Run 'artifacts' | Out-Null
    $cats = Get-As4ArtifactCatalog | Where-Object { $Ids -contains $_.Id }
    $i = 0; $res = @()
    foreach ($c in $cats) { $i++; if ($OnProgress) { & $OnProgress $i $cats.Count $c }
        if ($global:Cancel) { break }
        $res += Invoke-As4ArtifactCategory -Cat $c -Since $Since -Extensions $Extensions -MaxMB $MaxMB -Duplicates:$Duplicates }
    Stop-As4Run; $res
}

# Generic selected-folder collection (feature A)
function Invoke-As4FolderCollection {
    param([string[]]$Folders, $Since, $Until, [string[]]$Extensions, [double]$MaxMB = 0, [switch]$Duplicates, [switch]$InventoryOnly)
    $cat = @{ Id = 'custom_' + (Get-UtcStamp); Name = 'Custom folder collection'; Admin = 'none'; Files = @(); Inventory = @() }
    foreach ($f in $Folders) {
        $full = [IO.Path]::GetFullPath($f)
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { Write-As4Log WARN "Folder not found: $full"; continue }
        if ($full.StartsWith($global:Case.Dir, [StringComparison]::OrdinalIgnoreCase)) { Write-As4Log WARN "Refusing to collect from inside the case output folder: $full"; continue }
        if ($InventoryOnly) { $cat.Inventory += $full } else { $cat.Files += ($full.TrimEnd('\') + '\*|r') }
    }
    Start-As4Run 'folder-collection' | Out-Null
    $r = Invoke-As4ArtifactCategory -Cat ([pscustomobject]$cat) -Since $Since -Extensions $Extensions -MaxMB $MaxMB -Duplicates:$Duplicates
    Stop-As4Run; $r
}
