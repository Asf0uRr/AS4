# AS4 IR Tool self-test driver. Uses synthetic data and a throw-away case; never touches real evidence.
# Usage: powershell -File scripts\Run-SelfTests.ps1 [-Root <AS4 root>] [-ResultFile <path.md>]
param([string]$Root, [string]$ResultFile)
$ErrorActionPreference = 'Continue'
$root0 = Split-Path -Parent $PSScriptRoot; $app = Join-Path $root0 'app'; $tasksDir = Join-Path $root0 'tasks'
if (-not $Root) { $Root = $root0 }
. (Join-Path $app 'Core.ps1'); foreach ($f in 'QuickResponse', 'Persistence', 'EventLogs', 'Artifacts', 'Hayabusa', 'QuickScan', 'Chainsaw', 'Kape', 'Memory', 'Yara', 'IocSearch', 'Timeline', 'Integrity', 'Report', 'LiveHunt', 'LiveReport', 'LiveWatch', 'Scenarios', 'Package') { . (Join-Path $tasksDir "$f.ps1") }
Initialize-As4 -Root $Root
$global:R = New-Object Collections.ArrayList
function T { param($id, $name, [scriptblock]$body)
    try { $o = & $body; $res = if ($o -is [string] -and $o.StartsWith('BLOCKED:')) { 'BLOCKED' } elseif ($o -is [string] -and $o.StartsWith('FAIL:')) { 'FAIL' } else { 'PASS' }; $d = if ($o -is [string]) { $o } else { '' } }
    catch { $res = 'FAIL'; $d = $_.Exception.Message }
    [void]$global:R.Add([pscustomobject]@{ Id = $id; Test = $name; Result = $res; Detail = $d }); Write-Host ("{0,-5} {1,-8} {2}  {3}" -f $id, $res, $name, $d) }
function Assert { param($c, $m) if (-not $c) { throw "assertion failed: $m" } }

$stamp = (Get-Date).ToString('yyyyMMddHHmmss'); $cid = "SELFTEST-$stamp"
$synth = Join-Path ([IO.Path]::GetTempPath()) "as4_synth_$stamp"; New-Item -ItemType Directory $synth | Out-Null

T 'C01' 'Case name creates output\<name>; existing case resumes; bad names refused' {
    $c1 = Start-As4Case $cid; Assert (-not $c1.Resumed) 'new case'; Assert (Test-Path "$($global:Case.Dir)\00_Metadata\case.json") 'case.json'; Assert ($global:Case.Dir -eq (Join-Path $global:P.Output $cid)) 'folder is output\<name>'
    $c2 = Start-As4Case $cid; Assert $c2.Resumed 'second start resumes the same folder'
    foreach ($b in '..\evil', 'a/b', 'CON', '', 'x:y') { $bad = $false; try { Start-As4Case $b | Out-Null } catch { $bad = $true }; Assert $bad "name '$b' must be refused" }
    New-Item -ItemType Directory -Path (Join-Path $global:P.Output "plain_$stamp") | Out-Null; $bad = $false; try { Start-As4Case "plain_$stamp" | Out-Null } catch { $bad = $true }; Assert $bad 'non-AS4 folder must not be adopted'; Remove-Item (Join-Path $global:P.Output "plain_$stamp") -Force; Start-As4Case $cid | Out-Null
}
T 'C02' 'Evidence writer refuses to overwrite existing file' { $f = Join-Path $synth 'x.txt'; Write-As4File $f 'a'; $r = $false; try { Write-As4File $f 'b' } catch { $r = $true }; Assert $r 'must refuse'; Assert ((Get-Content $f -Raw) -eq 'a') 'content unchanged' }
T 'C03' 'Argument quoting handles spaces, quotes, trailing backslash' {
    $a = ConvertTo-ArgString @('a b', 'c"d', 'e\', 'f g\', '')
    Assert ($a -eq '"a b" "c\"d" e\ "f g\\" ""') "got: $a"
}
Start-As4Run 'selftest' | Out-Null
T 'N01' 'Native command OK: stdout, exit code, hash, manifest' {
    $r = Invoke-As4Task (New-As4Task @{ Id = 't_host'; Name = 'host'; Folder = 'Sys'; Type = 'native'; Exe = 'hostname.exe'; Args = @() })
    Assert ($r.Status -eq 'OK' -and $r.ExitCode -eq 0) "status $($r.Status)"; Assert ($r.Sha256[0].Length -eq 64) 'hash'
}
T 'N02' 'Command failure is FAILED with real exit code (file existing is not success)' {
    $r = Invoke-As4Task (New-As4Task @{ Id = 't_fail'; Name = 'fail'; Folder = 'Sys'; Type = 'native'; Exe = 'cmd.exe'; Args = @('/c', 'echo partial & exit 3') })
    Assert ($r.Status -eq 'FAILED' -and $r.ExitCode -eq 3) "status=$($r.Status) exit=$($r.ExitCode)"
}
T 'N03' 'stderr captured separately' {
    $r = Invoke-As4Task (New-As4Task @{ Id = 't_err'; Name = 'err'; Folder = 'Sys'; Type = 'native'; Exe = 'cmd.exe'; Args = @('/c', 'echo out& echo oops 1>&2') })
    Assert (@($r.Destination | Where-Object { $_ -like '*stderr*' }).Count -eq 1) 'stderr file'
}
T 'N04' 'Timeout kills process and reports TIMEOUT' {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-As4Task (New-As4Task @{ Id = 't_to'; Name = 'timeout'; Folder = 'Sys'; Type = 'native'; Exe = 'ping.exe'; Args = @('-n', '30', '127.0.0.1'); Timeout = 2 })
    Assert ($r.Status -eq 'TIMEOUT') "status $($r.Status)"; Assert ($sw.Elapsed.TotalSeconds -lt 15) 'returned promptly'
}
T 'N05' 'Missing command is SKIPPED, not a crash' { $r = Invoke-As4Task (New-As4Task @{ Id = 't_missing'; Name = 'missing'; Folder = 'Sys'; Type = 'native'; Exe = 'definitely_not_a_command_xyz.exe'; Args = @() }); Assert ($r.Status -eq 'SKIPPED') $r.Status }
T 'N06' 'Admin-required task is SKIPPED when not elevated (or runs when elevated)' {
    $r = Invoke-As4Task (New-As4Task @{ Id = 't_admin'; Name = 'admin'; Folder = 'Sys'; Type = 'native'; Exe = 'hostname.exe'; Args = @(); Admin = 'required' })
    if (Test-As4Admin) { Assert ($r.Status -eq 'OK') 'elevated run' } else { Assert ($r.Status -eq 'SKIPPED') $r.Status }
}
T 'N07' 'One failing task does not stop the batch' {
    $ts = @((New-As4Task @{ Id = 'b1'; Name = 'b1'; Folder = 'Sys'; Type = 'native'; Exe = 'cmd.exe'; Args = @('/c', 'exit 9') }), (New-As4Task @{ Id = 'b2'; Name = 'b2'; Folder = 'Sys'; Type = 'native'; Exe = 'hostname.exe'; Args = @() }))
    $r = Invoke-As4Batch -Tasks $ts; Assert ($r.Count -eq 2 -and $r[1].Status -eq 'OK') 'second task ran'
}
T 'N08' 'Cancellation: remaining tasks CANCELLED, completed evidence still verifies' {
    $ts = 1..4 | ForEach-Object { New-As4Task @{ Id = "c$_"; Name = "c$_"; Folder = 'Sys'; Type = 'native'; Exe = 'hostname.exe'; Args = @() } }
    $r = Invoke-As4Batch -Tasks $ts -OnProgress { param($i, $n, $t) if ($i -eq 3) { $global:Cancel = $true } }
    Assert (@($r | Where-Object Status -eq 'OK').Count -eq 2 -and @($r | Where-Object Status -eq 'CANCELLED').Count -eq 2) (($r | ForEach-Object Status) -join ',')
    $global:Cancel = $false; $v = Invoke-As4Verify $global:Case.Id; Assert ($v.Problems -eq 0) "problems=$($v.Problems)"
}
T 'N09' 'PowerShell-based task emits CSV+JSON+TXT' { $r = Invoke-As4Task (@(Get-As4QuickTasks | Where-Object Id -eq 'osinfo')[0]); Assert ($r.Status -eq 'OK' -and $r.Destination.Count -eq 3) "$($r.Status) files=$($r.Destination.Count)" }
T 'N10' 'Structured network connections (CSV) has process names' { $r = Invoke-As4Task (@(Get-As4QuickTasks | Where-Object Id -eq 'netconn')[0]); Assert ($r.Status -eq 'OK') $r.Status; $csv = Import-Csv (Join-Path $global:Case.Dir ($r.Destination | Where-Object { $_ -like '*.csv' })); Assert ($csv.Count -gt 0 -and ($csv | Where-Object Process).Count -gt 0) 'rows with process names' }
T 'N11' 'Triage tasks (runkeys, services, wmi, tasks, startup) run without crashing' {
    $ids = 'tri_runkeys', 'tri_services', 'tri_wmi', 'tri_tasks', 'tri_startupfolders', 'tri_netsus'
    $r = Invoke-As4Batch -Tasks @(Get-As4TriageTasks | Where-Object { $ids -contains $_.Id }); $bad = @($r | Where-Object { $_.Status -notin 'OK', 'SKIPPED' }); Assert (-not $bad.Count) (($bad | ForEach-Object { "$($_.TaskId):$($_.Status)" }) -join ',')
}
T 'E01' 'Event log export (Application) produces non-empty EVTX in raw_evtx' {
    $o = Export-As4Evtx -Channels @('Application'); Assert (@($o).Count -eq 1) "expected 1 path, got $(@($o).Count): $(@($o | ForEach-Object { '[' + $_.GetType().Name + ']' + $_ }) -join ' | ')"; Assert ((Get-Item -LiteralPath $o[0]).Length -gt 0) 'evtx non-empty'; Assert ($o[0] -like '*raw_evtx*') 'folder'
}
T 'E02' 'Missing channel -> SKIPPED; Security without admin -> SKIPPED' {
    Export-As4Evtx -Channels @('Microsoft-Windows-Does-Not-Exist/Operational', 'Security') | Out-Null
    $m = Get-As4Manifest $global:Case.Dir | Where-Object { $_.TaskId -in 'evtx:Microsoft-Windows-Does-Not-Exist/Operational', 'evtx:Security' }
    Assert (@($m | Where-Object Status -eq 'SKIPPED').Count -ge 1) 'skipped recorded'
    if (-not (Test-As4Admin)) { Assert (($m | Where-Object TaskId -eq 'evtx:Security').Status -eq 'SKIPPED') 'Security skipped' }
}
T 'E03' 'Filtered export is labelled derived and goes to filtered_evtx' {
    $q = New-As4EvtxQuery -StartUtc ((Get-Date).AddDays(-30)) -EventIds '1000,1001'; Assert ($q -match 'EventID=1000 or EventID=1001' -and $q -match "SystemTime>='") $q
    $o = Export-As4Evtx -Channels @('Application') -Query $q; Assert (@($o).Count -eq 1 -and "$($o[0])" -like '*filtered_evtx*') "filtered path: $(@($o) -join '|')"
    $bad = $false; try { New-As4EvtxQuery -EventIds '4624; calc' | Out-Null } catch { $bad = $true }; Assert $bad 'injection rejected'
}
T 'E04' 'Channel metadata (wevtutil gli) saved' { Assert (@(Get-ChildItem "$($global:Case.Dir)\05_Event_Logs" -Filter channel_metadata* -ErrorAction SilentlyContinue).Count -ge 1) 'metadata file' }

# synthetic folder collection
$src = Join-Path $synth 'src dir with spaces'; New-Item -ItemType Directory "$src\sub" | Out-Null
'alpha' | Set-Content "$src\a.exe"; 'alpha' | Set-Content "$src\sub\dup copy.exe"; 'beta' | Set-Content "$src\b.txt"; ('x' * 5000) | Set-Content "$src\big.dll"
(Get-Item "$src\a.exe").LastWriteTime = [datetime]'2020-01-02 03:04:05'
T 'A01' 'Folder collection: filters, relative paths, hashes, timestamps, duplicates' {
    $r = Invoke-As4FolderCollection -Folders @($src) -Extensions @('exe', 'txt') -Duplicates
    Assert ($r.Status -eq 'OK') $r.Status
    $inv = Import-Csv (Join-Path $global:Case.Dir ($r.Destination | Where-Object { $_ -like '*_inventory*' })); Assert (($inv | Where-Object Status -eq 'COPIED').Count -eq 3) 'extension filter (3 of 4 files)'
    $cp = Get-ChildItem "$($global:Case.Dir)\10_Artifacts" -Recurse -Filter 'a.exe' | Select-Object -First 1
    Assert ($cp.LastWriteTime -eq [datetime]'2020-01-02 03:04:05') 'last-write preserved'; Assert ((Get-As4Sha256 $cp.FullName) -eq (Get-As4Sha256 "$src\a.exe")) 'copy hash == source hash'
    Assert (@(Get-ChildItem "$($global:Case.Dir)\10_Artifacts" -Recurse -Filter '_duplicates*').Count -eq 1) 'duplicates report'
    Assert (Test-Path -LiteralPath $cp.FullName) 'preserved relative structure'
}
T 'A02' 'Missing artifacts are recorded, not fatal (non-admin categories)' {
    $r = Invoke-As4Artifacts -Ids @('powershell', 'tasks', 'netcfg', 'shimcache', 'services', 'ntfs', 'prefetch'); Assert ($r.Count -eq 7) 'all 7 processed'
    $pf = $r | Where-Object TaskId -eq 'artifact:prefetch'; if (-not (Test-As4Admin)) { Assert ($pf.Status -eq 'SKIPPED') 'prefetch skipped w/o admin' }
    $ntfs = $r | Where-Object TaskId -eq 'artifact:ntfs'; if (-not (Test-As4Admin)) { Assert ($ntfs.Status -eq 'SKIPPED') 'ntfs needs admin' }
}
T 'A03' 'Raw $MFT/$LogFile/$J are NOT claimed as collected' { $c = Get-As4ArtifactCatalog | Where-Object Id -eq 'ntfs'; Assert ($c.RawOnly.Count -eq 3 -and -not $c.Files) 'raw-only' }
$iocs = Join-Path $synth 'iocs.txt'; "# list`n203.0.113.77`nevil-c2.example.net`n" + ('a' * 64) | Set-Content $iocs
$hay = Join-Path $synth 'hay'; New-Item -ItemType Directory $hay | Out-Null
"conn to 203.0.113.77:443`nnothing here`nlookup EVIL-C2.example.net done" | Set-Content "$hay\log.txt"; ("sha " + ('a' * 64)) | Set-Content "$hay\h.csv"; [IO.File]::WriteAllBytes("$hay\bin.evtx", [byte[]](1..50))
T 'I01' 'IOC search finds IP/domain(case-insens)/hash; binary files listed as skipped' {
    $r = Invoke-As4IocSearch -IocFile $iocs -SearchRoot $hay; Assert ($r.Hits -eq 3) "hits=$($r.Hits)"; Assert ($r.Skipped -eq 1) "skipped=$($r.Skipped)"
    $h = Import-Csv $r.HitsFile; $tc = @($h | ForEach-Object Type) -join ','; Assert ((@($h | Where-Object Type -eq 'ipv4').Count -eq 1) -and (@($h | Where-Object Type -eq 'domain').Count -eq 1) -and (@($h | Where-Object Type -eq 'sha256').Count -eq 1)) "types=$tc"
}
T 'I02' 'Timeline: explicit-UTC rows high confidence, zone-less rows flagged UNCERTAIN' {
    $d = Join-Path $global:Case.Dir '10_Artifacts\synthetic'; New-Item -ItemType Directory $d -Force | Out-Null
    "Name,CreatedUtc,Modified`nx.exe,2020-01-01T10:00:00Z,2020-01-01 11:00:00" | Set-Content "$d\ts.csv"
    $r = Invoke-As4Timeline; $t = Import-Csv $r.File | Where-Object SourceFile -like '*synthetic*'
    Assert ($t.Count -eq 2) "rows=$($t.Count)"; Assert ((@($t | Where-Object { $_.Confidence -like 'High*' }).Count -eq 1) -and (@($t | Where-Object { $_.Confidence -like 'UNCERTAIN*' }).Count -eq 1)) "confidence: $(@($t | ForEach-Object Confidence) -join ' / ')"
    Assert (($t | Where-Object TimeField -eq 'CreatedUtc').TimestampUtc -eq '2020-01-01T10:00:00.000Z') 'utc normalised'
}
T 'R01' 'Hash ledger verifies; tampering and deletion are detected' {
    $v = Invoke-As4Verify $global:Case.Id; Assert ($v.Problems -eq 0 -and $v.Total -gt 10) "baseline problems=$($v.Problems) total=$($v.Total)"
    $f = Get-ChildItem "$($global:Case.Dir)\01_System_Info" -Filter 't_host*' | Select-Object -First 1; $orig = Get-Content $f.FullName -Raw
    Add-Content $f.FullName 'tamper'; $v2 = Invoke-As4Verify $global:Case.Id; Assert (@($v2.Details | Where-Object Status -eq 'MISMATCH').Count -eq 1) 'mismatch detected'
    [IO.File]::WriteAllText($f.FullName, $orig); $moved = "$($f.FullName).bak"; Move-Item $f.FullName $moved; $v3 = Invoke-As4Verify $global:Case.Id; Assert (@($v3.Details | Where-Object Status -eq 'MISSING').Count -eq 1) 'missing detected'; Move-Item $moved $f.FullName
}
T 'R02' 'Run seal files exist' { Assert (@(Get-ChildItem "$($global:Case.Dir)\00_Metadata" -Filter 'seal_*.sha256').Count -ge 1) 'seal' }
T 'R03' 'Report matches manifest counts and avoids compromise claims' {
    $r = New-As4Report $global:Case.Id; $h = Get-Content $r.Html -Raw; $m = @(Get-As4Manifest $global:Case.Dir)
    foreach ($g in ($m | Group-Object Status)) { Assert ($h -match [regex]::Escape("$($g.Name): $($g.Count)")) "count for $($g.Name)" }
    Assert ($h -match 'not confirmed compromise') 'disclaimer'; Assert (Test-Path $r.Csv) 'csv'; Assert (Test-Path $r.Json) 'json'
}
# integrations
$ci = Get-ChainsawInfo -Refresh
T 'H01' 'Chainsaw detected and registered/verified against manifest hash' { Assert $ci.Present 'present'; $t = Get-As4Tool 'chainsaw'; Assert ($t.Status -eq 'PRESENT_VERIFIED') $t.Status; "status=$($t.Status)" }
T 'H02' 'Chainsaw executes on this host (version + real help)' { if (-not $ci.Runnable) { "BLOCKED: cannot execute chainsaw: $($ci.BlockReason)" } else { Assert ($ci.Version) 'version'; Assert ($ci.Flags['hunt'].Count -gt 0) 'hunt flags'; "version=$($ci.Version)" } }
T 'H03' 'Chainsaw hunt on EVTX using real binary' { if (-not $ci.Runnable) { 'BLOCKED: binary cannot execute here' } else { $e = Get-ChildItem "$($global:Case.Dir)\05_Event_Logs\raw_evtx" -Filter *.evtx | Select-Object -First 1; $r = Invoke-Chainsaw -Sub hunt -O @{ Input = @($e.DirectoryName); Format = 'json'; Rules = $ci.Rules; SkipErrors = $true }; Assert ($r.Status -in 'OK') $r.Status } }
T 'H04' 'Chainsaw runner reports SKIPPED with reason when binary blocked/missing (never reports a success it did not get)' { if ($ci.Runnable) { 'BLOCKED: only applicable when the binary cannot run' } else { $r = Invoke-Chainsaw -Sub hunt -O @{ Input = @($synth) }; Assert ($r.Status -eq 'SKIPPED' -and (@($r.Notes) -join ' ') -match 'cannot execute') "status=$($r.Status)" } }
T 'H05' 'Chainsaw arg builder only emits flags present in help (synthetic help text, NOT the real binary)' {
    $save = $global:ChainsawCache
    $global:ChainsawCache = [pscustomobject]@{ Flags = @{ hunt = @('--sigma', '--mapping', '--rule', '--csv', '--output', '--skip-errors', '--level'); search = @() } }
    $b = Build-ChainsawArgs 'hunt' @{ Sigma = 'S'; Mapping = 'M'; Rules = 'R'; Format = 'json'; Output = 'O'; Input = @('E'); From = '2020' }
    $global:ChainsawCache = $save
    Assert ($b.Args -contains '--sigma' -and $b.Args -contains '--output' -and $b.Args -notcontains '--json' -and $b.Args -notcontains '--from') ($b.Args -join ' '); Assert ($b.Notes.Count -ge 2) 'notes about unsupported flags'
}
T 'H06' 'Chainsaw result loader parses CSV/JSON (synthetic sample)' {
    $j = Join-Path $synth 'r.json'; '[{"name":"Rule A","level":"high","timestamp":"2020-01-01T00:00:00Z","status":"stable","group":"Sigma","kind":"individual","authors":["x"],"count":1}]' | Set-Content $j
    $r = @(Import-ChainsawResults $j); Assert ($r.Count -eq 1 -and $r[0].Detection -eq 'Rule A') 'json'
}
T 'K01' 'KAPE is detected with its real Targets and Modules' { $k = Get-KapeInfo; if (-not $k.Present) { 'BLOCKED: kape.exe not bundled' } else { Assert $k.Runnable "kape cannot run: $($k.BlockReason)"; Assert ($k.Targets.Count -gt 100 -and $k.Modules.Count -gt 100) "targets=$($k.Targets.Count) modules=$($k.Modules.Count)"; "KAPE $($k.Version): targets=$($k.Targets.Count) modules=$($k.Modules.Count)" } }
T 'K02' 'KAPE run is SKIPPED without administrator and refuses unknown targets' { if (Test-As4Admin) { 'BLOCKED: elevated - live collection not auto-run' } else { $r = Invoke-Kape -Targets @('!SANS_Triage'); Assert ($r.Status -eq 'SKIPPED') $r.Status } }
T 'K03' 'Every target and module named in the KAPE scenario profiles exists in the bundled KAPE' { if (-not (Get-KapeInfo).Present) { 'BLOCKED: kape.exe not bundled' } else { $ps = @(Get-KapeProfiles); Assert ($ps.Count -eq 8) "profiles=$($ps.Count)"; $m = @($ps | ForEach-Object { $_.MissingTargets + $_.MissingModules } | Where-Object { $_ }); Assert (-not $m.Count) ("missing: " + ($m -join ', ')) } }
T 'M01' 'WinPmem is SKIPPED without administrator (never auto-runs when elevated); space check works' { $s = Test-MemorySpace $synth; Assert ($s.RamBytes -gt 0 -and $s.FreeBytes -gt 0) 'space check'; if (Test-As4Admin) { 'BLOCKED: elevated session - acquisition is not auto-run' } else { $r = Invoke-MemoryAcquisition -ToolId winpmem -DestDir $synth -ArgTemplate '{OUT}'; Assert ($r.Status -eq 'SKIPPED') $r.Status } }
T 'M02' 'Real memory acquisition with WinPmem' { $t = Get-As4Tool 'winpmem'; if (-not $t.Path) { 'BLOCKED: no WinPmem binary bundled' } else { 'BLOCKED: needs an elevated session and an analyst decision (intrusive); not auto-run' } }
T 'M03' 'FTK Imager: Register output hashes a synthetic .mem and rejects an empty disk folder; FTK GUI launch is manual (UAC)' {
    $md = Get-CaseFolder 'Mem'; [IO.File]::WriteAllBytes("$md\synthetic_test.mem", [byte[]](1..200)); 'x' | Set-Content "$md\synthetic_test.mem.txt"
    $r2 = Register-FtkOutput -Mode memory; Assert ($r2.Status -eq 'OK') "register: $($r2.Status) $(@($r2.Notes) -join ' ')"
    $led = Import-Csv "$($global:Case.Dir)\00_Metadata\hashes.csv" | Where-Object RelativePath -like '*synthetic_test.mem'; Assert (@($led).Count -ge 1 -and $led[0].Sha256.Length -eq 64) 'ledger entry'
    $e2 = Register-FtkOutput -Mode disk; Assert ($e2.Status -eq 'FAILED') 'disk register with no image must FAIL'
    if (-not (Get-As4Tool 'ftkimager').Path) { 'BLOCKED: FTK Imager not bundled' } else { 'BLOCKED (launch only): FTK Imager is bundled; opening it needs a UAC prompt, so it is a manual test' } }
T 'Y01' 'YARA scan with the bundled yara64.exe finds a synthetic match' { $t = Get-As4Tool 'yara'; if (-not $t.Path) { 'BLOCKED: yara not bundled' } else {
    $rule = Join-Path $synth 't.yar'; 'rule as4_test { strings: $a = "AS4-SYNTHETIC-MARKER" condition: $a }' | Set-Content $rule; $tg = Join-Path $synth 'yt'; New-Item -ItemType Directory $tg | Out-Null; 'hello AS4-SYNTHETIC-MARKER' | Set-Content "$tg\a.txt"; 'clean' | Set-Content "$tg\b.txt"
    $r = Invoke-Yara -Rules $rule -Target $tg; Assert ($r.Status -eq 'OK') "status $($r.Status) $(@($r.Notes) -join ' ')"; $m = Get-Content (Join-Path $global:Case.Dir ($r.Destination | Where-Object { $_ -like '*yara_matches*' })) -Raw; Assert ($m -match 'as4_test' -and $m -match 'a\.txt' -and $m -notmatch 'b\.txt') $m } }
T 'Y03' 'Bundled community YARA rule set (534 files) compiles into an index' { $t = Get-As4Tool 'yara'; if (-not $t.Path) { 'BLOCKED: yara not bundled' } else { $d = Join-Path $global:P.Rules 'yara\community'; if (-not (Test-Path $d)) { return 'BLOCKED: community YARA rule set not bundled in this copy' }; $ix = New-YaraIndex $d (Get-CaseFolder 'Rep'); Assert ($ix.Compiled -gt 300) "compiled=$($ix.Compiled) skipped=$(@($ix.Skipped).Count)"; "compiled $($ix.Compiled) of 534, skipped $(@($ix.Skipped).Count)" } }
T 'Y02' 'YARA with a rule folder: compiles each rule, skips broken ones, scans' { $t = Get-As4Tool 'yara'; if (-not $t.Path) { 'BLOCKED: yara not bundled' } else { $rd = Join-Path $synth 'rd'; New-Item -ItemType Directory $rd | Out-Null; 'rule good_one { strings: $a = "ZZ-AS4-FOLDER" condition: $a }' | Set-Content "$rd\good.yar"; 'rule broken { condition: nonsense( }' | Set-Content "$rd\bad.yar"; $tg = Join-Path $synth 'yt2'; New-Item -ItemType Directory $tg | Out-Null; 'ZZ-AS4-FOLDER' | Set-Content "$tg\x.txt"; $r = Invoke-Yara -Rules $rd -Target $tg; Assert ($r.Status -eq 'OK') "status $($r.Status) $(@($r.Notes) -join ' ')"; Assert ((@($r.Notes) -join ' ') -match '1 rule files used, 1 skipped') (@($r.Notes) -join ' ') } }
T 'V01' 'Volatility on a non-dump file reports FAILED, never OK' { $t = Get-As4Tool 'volatility3'; if (-not $t.Path) { 'BLOCKED: volatility not bundled' } else { $f = Join-Path $synth 'notadump.mem'; [IO.File]::WriteAllBytes($f, [byte[]](1..255)); $r = Invoke-Volatility -Dump $f -Plugin windows.info; Assert ($r.Status -ne 'OK') $r.Status } }
T 'V02' 'Volatility on a real memory dump' { 'BLOCKED: no real memory dump available on this workstation (none available)' }
T 'A04' 'Autoruns (autorunsc64) runs and returns rows' { $t = Get-As4Tool 'autorunsc'; if (-not $t.Path) { 'BLOCKED: autorunsc not bundled' } else { $r = Invoke-Autoruns; Assert ($r.Status -eq 'OK') "status $($r.Status) exit=$($r.ExitCode) $(@($r.Notes) -join ' ')"; $o = Join-Path $global:Case.Dir ($r.Destination | Select-Object -First 1); Assert ((Import-Csv $o).Count -gt 0) 'rows' } }
T 'T01' 'Downloaded tools are registered and verified against recorded hashes' { $bad = @(); foreach ($id in 'hayabusa', 'chainsaw', 'kape', 'ftkimager', 'winpmem', 'yara', 'volatility3', 'autorunsc', 'sigcheck', 'handle', 'listdlls', 'pstools', 'tcpview', 'strings') { $t = Get-As4Tool $id; if ($t.Path -and $t.Status -ne 'PRESENT_VERIFIED') { $bad += "$id=$($t.Status)" } }; Assert (-not $bad.Count) ($bad -join ', ') }
$hy = Get-HayabusaInfo
$tiny = Join-Path $synth 'tiny'; New-Item -ItemType Directory $tiny | Out-Null; & wevtutil.exe epl Application "$tiny\t.evtx" '/q:*[System[(EventID=1000 or EventID=1001 or EventID=11707)]]' /ow:true
$rich = Join-Path $synth 'rich'; New-Item -ItemType Directory $rich | Out-Null; & wevtutil.exe epl Application "$rich\Application.evtx" /ow:true; & wevtutil.exe epl "Microsoft-Windows-PowerShell/Operational" "$rich\PowerShell.evtx" /ow:true
T 'HB01' 'Hayabusa detected, runs, version and rules present, hash verified' { if (-not $hy.Present) { 'BLOCKED: Hayabusa not bundled' } else { Assert $hy.Runnable "cannot run: $($hy.BlockReason)"; Assert ($hy.RuleFiles -gt 1000) "rules=$($hy.RuleFiles)"; Assert ((Get-As4Tool 'hayabusa').Status -eq 'PRESENT_VERIFIED') 'manifest'; "$($hy.Version), $($hy.RuleFiles) rule files" } }
T 'HB02' 'Option parser: every option in each command help is parsed (no option lost)' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $miss = @(); foreach ($c in $global:HayCommands.Keys) { $sp = Get-HayabusaSpec $c; $raw = @([regex]::Matches($sp.Help, '(?m)^\s+(?:-[A-Za-z],\s+)?--[A-Za-z0-9-]+')).Count; $got = @($sp.Sections | ForEach-Object { $_.Options }).Count; if ($raw -ne $got -or $got -eq 0) { $miss += "$c raw=$raw parsed=$got" } }
    Assert (-not $miss.Count) ($miss -join '; '); "all $($global:HayCommands.Count) commands parsed" } }
T 'HB03' 'dfir-timeline on a real exported EVTX: CSV with header, HTML report, arguments recorded, hashes ledgered' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $r = Invoke-Hayabusa -Command dfir-timeline -InSpec @{ Kind = 'directory'; Path = $rich } -Options @{ 'min-level' = 'low'; 'profile' = 'standard'; 'utc' = $true; 'html-report' = $true }
    Assert ($r.Status -eq 'OK') "status $($r.Status) $(@($r.Notes) -join ' ')"; $d = @($r.Destination)
    Assert (@($d | Where-Object { $_ -like '*timeline.csv' }).Count -eq 1) 'timeline.csv'; Assert (@($d | Where-Object { $_ -like '*report.html' }).Count -eq 1) 'report.html'; Assert (@($d | Where-Object { $_ -like '*arguments.json' }).Count -eq 1) 'arguments.json'
    $csv = Join-Path $global:Case.Dir (@($d | Where-Object { $_ -like '*timeline.csv' })[0]); $hd = (Get-Content $csv -TotalCount 1); Assert ($hd -match 'Timestamp' -and $hd -match 'RuleTitle' -and $hd -match 'Level') $hd
    Assert ($r.Arguments -match '--min-level low' -and $r.Arguments -match '--utc') $r.Arguments } }
T 'HB04' 'Bad input is refused before running (level, missing input, search without pattern, unknown option warned)' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $a = Invoke-Hayabusa -Command dfir-timeline -InSpec @{ Kind = 'directory'; Path = $tiny } -Options @{ 'min-level' = 'banana' }; Assert ($a.Status -eq 'FAILED') "level: $($a.Status)"
    $b = Invoke-Hayabusa -Command dfir-timeline -InSpec @{ Kind = 'none' } -Options @{}; Assert ($b.Status -eq 'FAILED') "no input: $($b.Status)"
    $c = Invoke-Hayabusa -Command search -InSpec @{ Kind = 'directory'; Path = $tiny } -Options @{}; Assert ($c.Status -eq 'FAILED') "search: $($c.Status)"
    $d = Invoke-Hayabusa -Command dfir-timeline -InSpec @{ Kind = 'directory'; Path = (Join-Path $synth 'nope') } -Options @{}; Assert ($d.Status -eq 'FAILED') "missing folder: $($d.Status)"
    $e = Invoke-Hayabusa -Command eid-metrics -InSpec @{ Kind = 'directory'; Path = $tiny } -Options @{ 'made-up-option' = $true }; Assert ($e.Status -eq 'OK' -and (@($e.Warnings) -join ' ') -match 'not an option') 'unknown option should be skipped with a warning' } }
T 'HB05' 'search, logon-summary, eid-metrics, computer-metrics, log-metrics, extract-base64, pivot-keywords-list, sort-csv run OK' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $in = @{ Kind = 'directory'; Path = $tiny }; $bad = @()
    foreach ($c in 'search', 'logon-summary', 'eid-metrics', 'computer-metrics', 'log-metrics', 'extract-base64', 'pivot-keywords-list') { $o = @{ utc = $true }; if ($c -eq 'search') { $o = @{ keyword = 'error'; 'ignore-case' = $true; 'json-output' = $true } }; $r = Invoke-Hayabusa -Command $c -InSpec $in -Options $o; if ($r.Status -ne 'OK') { $bad += "$c=$($r.Status) $(@($r.Notes) -join ' ')" } }
    $tl = Get-ChildItem "$($global:Case.Dir)\11_Hayabusa_Analysis" -Recurse -Filter timeline.csv | Select-Object -First 1
    $r = Invoke-Hayabusa -Command sort-csv -InSpec @{ Kind = 'file'; Path = $tl.FullName } -Options @{}; if ($r.Status -ne 'OK') { $bad += "sort-csv=$($r.Status) $(@($r.Notes) -join ' ')" }
    Assert (-not $bad.Count) ($bad -join ' | ') } }
T 'HB06' 'All Hayabusa presets build valid command lines' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $n = 0; foreach ($pr in Get-HayabusaPresets) { $o = @{}; foreach ($pp in $pr.Options.PSObject.Properties) { if ($pp.Value) { $o[$pp.Name] = $pp.Value } }; $null = Build-HayabusaArgs -Command $pr.Command -InSpec @{ Kind = 'directory'; Path = $tiny } -Options $o -OutDir $synth; $n++ }; Assert ($n -ge 10) "presets=$n"; "$n presets" } }
T 'HB07' 'Every option and filter of every command is accepted by the Hayabusa binary (executed one by one on a tiny EVTX)' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $sample = @{ '--min-level' = 'medium'; '--exact-level' = 'high'; '--output-type' = 'csv'; '--profile' = 'minimal'; '--time-offset' = '1y'; '--threads' = '2'; '--timeline-start' = '2020-01-01 00:00:00 +00:00'; '--timeline-end' = '2030-01-01 00:00:00 +00:00'; '--regex' = 'Application'; '--keyword' = 'error'; '--rules' = $hy.Rules; '--rules-config' = $hy.Config }
    $exempt = '--geo-ip', '--json-input'; $bad = @(); $n = 0; $od = Join-Path $synth 'hopt'; New-Item -ItemType Directory $od | Out-Null
    foreach ($c in 'dfir-timeline', 'search', 'logon-summary', 'eid-metrics', 'computer-metrics', 'log-metrics', 'extract-base64', 'pivot-keywords-list') {
        foreach ($sec in (Get-HayabusaSpec $c).Sections) { foreach ($o in $sec.Options) {
            if (($global:HayHidden -contains $o.Long -and $o.Long -ne '--html-report') -or $exempt -contains $o.Long) { continue }
            $k = $o.Long.Substring(2); $opts = @{}
            if ($o.Value) { $v = if ($sample.ContainsKey($o.Long)) { $sample[$o.Long] } else { 'x' }; foreach ($m in @(@('computer', 'NOPE'), @('eid', '1000'), @('status', 'stable'), @('tag', 'attack.execution'), @('category', 'process_creation'), @('channel', 'Application'), @('filename', 't.evtx'), @('file-ext', 'evtx'), @('filter', 'Channel'))) { if ($o.Long -match $m[0]) { $v = $m[1] } }; if ($sample.ContainsKey($o.Long)) { $v = $sample[$o.Long] }; $opts[$k] = $v } else { $opts[$k] = $true }
            if ($c -eq 'search' -and $k -notin 'keyword', 'regex') { $opts['keyword'] = 'error' }
            $n++; $w = Join-Path $od "r$n"; New-Item -ItemType Directory $w | Out-Null
            $b = Build-HayabusaArgs -Command $c -InSpec @{ Kind = 'directory'; Path = $tiny } -Options $opts -OutDir $w
            Assert ($b.Args -contains $o.Long) "$c $($o.Long) missing from the command line"
            $x = Invoke-As4Native -Exe $hy.Path -Arguments $b.Args -TimeoutSec 180 -WorkDir $(if ($b.NeedsToolDir) { $hy.Dir } else { $w })
            if ($x.ExitCode -ne 0 -or $x.TimedOut) { $bad += "$c $($o.Long) exit=$($x.ExitCode)" } } } }
    Assert (-not $bad.Count) ($bad -join '; '); "$n option runs, all accepted (--geo-ip needs a MaxMind database and --json-input needs JSON logs: built, not executed)" } }
T 'HS01' 'Scenario file: 21 scenarios, unique ids, valid commands, every option exists in that command, event IDs are numeric' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $sc = @(Get-HayabusaScenarios); Assert ($sc.Count -ge 20) "count=$($sc.Count)"; Assert (@($sc | Select-Object -ExpandProperty Id -Unique).Count -eq $sc.Count) 'unique ids'
    foreach ($s in $sc) { Assert ($global:HayCommands.Contains($s.Command)) "$($s.Id): command $($s.Command)"; $has = @{}; foreach ($sec in (Get-HayabusaSpec $s.Command).Sections) { foreach ($o in $sec.Options) { $has[$o.Long] = 1 } }
        foreach ($pp in $s.Options.PSObject.Properties) { Assert $has.ContainsKey("--$($pp.Name)") "$($s.Id): --$($pp.Name) is not an option of $($s.Command)" }
        if ($s.Options.'include-eid') { foreach ($x in ("$($s.Options.'include-eid')" -split ',')) { Assert ($x -match '^\d{1,5}$') "$($s.Id): bad event id $x" } }
        if ($s.Filter) { [void][regex]::new($s.Filter) } }
    "$($sc.Count) scenarios" } }
T 'HS02' 'Multi-value options are sent as one comma-separated value; simple choices become real options' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $b = Build-HayabusaArgs -Command dfir-timeline -InSpec @{ Kind = 'directory'; Path = $tiny } -Options @{ 'include-eid' = '4624, 4625;1149' } -OutDir $synth; $ix = [array]::IndexOf($b.Args, '--include-eid'); Assert ($ix -ge 0 -and $b.Args[$ix + 1] -eq '4624,4625,1149') ($b.Args -join ' ')
    $sc = (Get-HayabusaScenarios | Where-Object Id -eq 'serious'); $o = (New-HayScenarioOptions -Scenario $sc -Time '7d' -Severity 'medium' -Html $true).Options
    Assert ($o['time-offset'] -eq '7d' -and $o['min-level'] -eq 'high' -and $o['utc'] -and $o['html-report']) 'scenario min-level high must not be lowered by a lower choice'
    $o2 = (New-HayScenarioOptions -Scenario (Get-HayabusaScenarios | Where-Object Id -eq 'rdp') -Time 'custom' -From '2026-10-01' -To '2026-10-05' -Severity 'high').Options; Assert ($o2['timeline-start'] -eq '2026-10-01 00:00:00 +00:00' -and $o2['timeline-end'] -eq '2026-10-05 23:59:59 +00:00' -and $o2['min-level'] -eq 'high') ($o2.Keys -join ',')
    $bad = $false; try { New-HayScenarioOptions -Scenario $sc -Time 'custom' -From 'yesterday' | Out-Null } catch { $bad = $true }; Assert $bad 'bad date must be refused' } }
T 'HS03' 'Log hints: a scenario warns when the needed log type is not in the folder' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $d = Join-Path $synth 'names'; New-Item -ItemType Directory $d | Out-Null; foreach ($n in 'Security_x.evtx', 'Microsoft-Windows-PowerShell%4Operational_x.evtx') { [IO.File]::WriteAllBytes("$d\$n", [byte[]](1, 2)) }
    $rdp = Get-HayabusaScenarios | Where-Object Id -eq 'rdp'; $ps = Get-HayabusaScenarios | Where-Object Id -eq 'powershell'
    $m = @(Test-ScenarioLogs $rdp @{ Kind = 'directory'; Path = $d }); Assert ($m -contains 'TerminalServices' -and $m -notcontains 'Security') ($m -join ','); Assert (@(Test-ScenarioLogs $ps @{ Kind = 'directory'; Path = $d }).Count -eq 0) 'powershell log present' } }
T 'HS04' 'All 21 scenarios run on real exported logs; none fails; PowerShell scenario finds events; scenario filter writes findings_filtered.csv' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $bad = @(); $found = @{}; foreach ($s in (Get-HayabusaScenarios)) { $r = Invoke-HayabusaScenario -Scenario $s -InSpec @{ Kind = 'directory'; Path = $rich } -Time 'all' -Severity 'all' -Html $false; if ($r.Status -notin 'OK', 'SKIPPED') { $bad += "$($s.Id)=$($r.Status) $(@($r.Notes) -join ' ')" }; $found[$s.Id] = (Get-HayabusaFindings $r).Total
        if ($s.Filter -and $r.Status -eq 'OK' -and -not (@($r.Destination) -like '*findings_filtered.csv')) { $bad += "$($s.Id): no findings_filtered.csv" } }
    Assert (-not $bad.Count) ($bad -join ' | '); Assert ($found['powershell'] -gt 0) 'powershell scenario found nothing in the PowerShell log'; "powershell=$($found['powershell']) serious=$($found['serious']) all_rules=$($found['all_rules'])" } }
T 'QS01' 'Quick Scan scoring on synthetic rows: cleared log + credential theft + service + password guessing that succeeded -> serious; no rows -> "No rule matched"' {
    $u = [char]0xA6; $rows = @(
        [pscustomobject]@{ Timestamp = '2026-10-01 10:00:00.000 +00:00'; RuleTitle = 'Security Log Cleared'; Level = 'high'; Computer = 'PC1'; Channel = 'Sec'; EventID = '1102'; MitreTactics = 'Stealth'; Details = 'User: bob' },
        [pscustomobject]@{ Timestamp = '2026-10-01 10:05:00.000 +00:00'; RuleTitle = 'Mimikatz Command Line'; Level = 'crit'; Computer = 'PC1'; Channel = 'Sec'; EventID = '4688'; MitreTactics = 'CredAccess'; Details = 'User: bob' },
        [pscustomobject]@{ Timestamp = '2026-10-01 10:06:00.000 +00:00'; RuleTitle = 'New Service Installed'; Level = 'med'; Computer = 'PC1'; Channel = 'Sys'; EventID = '7045'; MitreTactics = "Persis $u PrivEsc"; Details = 'User: alice' })
    1..12 | ForEach-Object { $rows += [pscustomobject]@{ Timestamp = "2026-10-01 09:0$($_ % 10):00.000 +00:00"; RuleTitle = 'Logon Failure'; Level = 'info'; Computer = 'PC1'; Channel = 'Sec'; EventID = '4625'; MitreTactics = ''; Details = "Src IP: 203.0.113.9 $u User: root" } }
    $rows += [pscustomobject]@{ Timestamp = '2026-10-01 09:30:00.000 +00:00'; RuleTitle = 'Logon (Network)'; Level = 'info'; Computer = 'PC1'; Channel = 'Sec'; EventID = '4624'; MitreTactics = ''; Details = 'Src IP: 203.0.113.9 User: root' }
    $a = Get-QsAnalysis -Rows $rows -Coverage $null -Second $null
    Assert ($a.Verdict -eq 'Serious indicators' -and $a.Score -ge 80) "verdict $($a.Verdict) score $($a.Score)"; Assert (@($a.Reasons | Where-Object { $_.Text -match 'failed to log on many times' }).Count -eq 1) 'brute-force success reason'
    Assert (($a.Chain | Where-Object Key -eq 'Persis').All -eq 1 -and ($a.Chain | Where-Object Key -eq 'PrivEsc').All -eq 1) 'tactic split on the separator'; Assert ($a.Window -and $a.Window.Hours -gt 0) 'incident window'; Assert (@($a.Ips | Where-Object Value -eq '203.0.113.9').Count -eq 1) 'address listed'
    $z = Get-QsAnalysis -Rows @() -Coverage $null -Second $null; Assert ($z.Verdict -eq 'No rule matched' -and $z.Score -eq 0) $z.Verdict }
T 'QS02' 'Quick Scan finds log folders in a case, skips AS4 output and filtered copies, and does not scan the same logs twice' {
    $root = Join-Path $synth 'qscase'; foreach ($d in '05_Event_Logs\raw_evtx', '05_Event_Logs\filtered_evtx', '06_KAPE\copy', '11_Hayabusa_Analysis\x', '10_Artifacts\other') { New-Item -ItemType Directory (Join-Path $root $d) -Force | Out-Null }
    foreach ($d in '05_Event_Logs\raw_evtx', '05_Event_Logs\filtered_evtx', '06_KAPE\copy', '11_Hayabusa_Analysis\x') { [IO.File]::WriteAllBytes((Join-Path $root "$d\System.evtx"), [byte[]](1..40)) }
    [IO.File]::WriteAllBytes((Join-Path $root '10_Artifacts\other\Security.evtx'), [byte[]](1..90))
    $f = @(Find-As4LogDirs $root); Assert ($f.Count -eq 2) "folders=$($f.Count): $(($f | ForEach-Object Dir) -join '; ')"; Assert ($f[0].Dir -like '*raw_evtx') 'raw_evtx first'; Assert (-not (@($f | Where-Object { $_.Dir -match 'filtered_evtx|11_Hayabusa|06_KAPE' }).Count)) 'duplicates and outputs skipped' }
T 'QS03' 'Quick Scan coverage: missing log types become blind spots; Security log starting much later than System is flagged' {
    $rows = @([pscustomobject]@{ Filename = 'System_1.evtx'; Events = '1,000'; 'First Timestamp' = '2026-01-01 00:00:00.000 +00:00'; 'Last Timestamp' = '2026-10-01 00:00:00.000 +00:00' }, [pscustomobject]@{ Filename = 'Security_1.evtx'; Events = '50'; 'First Timestamp' = '2026-09-25 00:00:00.000 +00:00'; 'Last Timestamp' = '2026-10-01 00:00:00.000 +00:00' })
    $c = Get-QsCoverage -Rows $rows -Names @('System_1.evtx', 'Security_1.evtx'); Assert ($c.Types['Security'] -and $c.Types['System'] -and -not $c.Types['Sysmon']) 'types'; Assert (@($c.Flags | Where-Object { $_ -match 'Security log starts' }).Count -eq 1) ($c.Flags -join '; ')
    $a = Get-QsAnalysis -Rows @() -Coverage $c -Second $null; Assert (@($a.Blind | Where-Object { $_ -match 'Sysmon' }).Count -eq 1 -and @($a.Blind | Where-Object { $_ -match 'Security log starts' }).Count -eq 1) ($a.Blind -join ' | ') }
T 'QS04' 'Quick Scan on real exported logs: verdict, HTML and text summary saved and hashed, no external URLs, fast mode finds no more than full mode, Chainsaw second opinion' { if (-not $hy.Runnable) { 'BLOCKED: Hayabusa cannot run' } else {
    $full = Invoke-QuickScan -Source @{ Kind = 'directory'; Path = $rich } -SecondOpinion:((Get-ChainsawInfo).Runnable); Assert ($full.Status -eq 'OK' -and $full.Analysis) "status $($full.Status) $(@($full.Notes) -join ' ')"; $a = $full.Analysis
    Assert ($a.Total -gt 0 -and $a.Score -gt 0) 'findings'; Assert (Test-Path $a.HtmlPath) 'html'; Assert (Test-Path $a.TextPath) 'txt'; Assert (-not (Select-String -Path $a.HtmlPath -Pattern 'https?://' -Quiet)) 'summary must not reference external URLs'
    $led = (Import-Csv "$($global:Case.Dir)\00_Metadata\hashes.csv").RelativePath; Assert (@($led | Where-Object { $_ -like '*quickscan_summary*' }).Count -ge 2) 'summary files in the hash ledger'
    Assert (@($a.Blind | Where-Object { $_ -match 'No Security log' }).Count -eq 1) 'blind spot for missing Security log'; if ((Get-ChainsawInfo).Runnable) { Assert ($a.Second -and $a.Second.Status -eq 'OK') 'second opinion' }
    $fast = Invoke-QuickScan -Source @{ Kind = 'directory'; Path = $rich } -Fast; Assert ($fast.Status -eq 'OK' -and $fast.Analysis.Total -le $a.Total) "fast=$($fast.Analysis.Total) full=$($a.Total)"; "verdict=$($a.Verdict) score=$($a.Score) total=$($a.Total) fast=$($fast.Analysis.Total)" } }
T 'QS05' 'Gentle on the endpoint: child tools run at BelowNormal priority and Hayabusa is limited to half the cores' {
    $x = Invoke-As4Native -Exe 'powershell.exe' -Arguments @('-NoProfile', '-Command', '(Get-Process -Id $PID).PriorityClass') -TimeoutSec 60; Assert ($x.StdOut.Trim() -eq 'BelowNormal') "priority=$($x.StdOut.Trim())"
    if ($hy.Runnable) { $b = Build-HayabusaArgs -Command dfir-timeline -InSpec @{ Kind = 'directory'; Path = $tiny } -Options @{} -OutDir $synth; $ix = [array]::IndexOf($b.Args, '--threads'); Assert ($ix -ge 0 -and [int]$b.Args[$ix + 1] -eq [math]::Max(1, [math]::Floor([Environment]::ProcessorCount / 2))) ($b.Args -join ' ')
        $b2 = Build-HayabusaArgs -Command dfir-timeline -InSpec @{ Kind = 'directory'; Path = $tiny } -Options @{ threads = '3' } -OutDir $synth; $j = [array]::IndexOf($b2.Args, '--threads'); Assert ($b2.Args[$j + 1] -eq '3' -and @($b2.Args | Where-Object { $_ -eq '--threads' }).Count -eq 1) 'analyst choice wins' } }
Add-Type -Namespace RtT -Name N -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern System.IntPtr LoadLibraryEx(string f, System.IntPtr h, uint flags); [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern bool FreeLibrary(System.IntPtr h);'
T 'RT01' 'PE reader: machine type and imported DLLs of a real program (no execution)' { $y = Get-As4Tool 'yara'; if (-not $y.Path) { 'BLOCKED: yara not bundled' } else { $pi = Get-PeInfo $y.Path; Assert ($pi -and $pi.X64) 'x64'; Assert (@($pi.Imports | Where-Object { $_ -match '^VCRUNTIME140\.dll$' }).Count -eq 1) ($pi.Imports -join ',') } }
T 'RT02' 'Self-repair: a program copied to a folder without its Visual C++ runtime gets the DLL from tools\_runtime' { $y = Get-As4Tool 'yara'; if (-not $y.Path) { 'BLOCKED: yara not bundled' } else {
    $d = Join-Path $synth 'rtfix'; New-Item -ItemType Directory $d | Out-Null; Copy-Item $y.Path $d; Assert (-not (Test-Path "$d\vcruntime140.dll")) 'precondition'
    $x = @(Repair-As4ToolRuntimes -Folders @($d)); Assert (@($x | Where-Object { $_.Dll -match 'vcruntime140' -and $_.Ok }).Count -eq 1) 'copied'; Assert ((Get-As4Sha256 "$d\vcruntime140.dll") -eq (Get-As4Sha256 (Join-Path $global:P.Tools '_runtime\x64\vcruntime140.dll'))) 'identical to the bundled Microsoft file'
    $x2 = @(Repair-As4ToolRuntimes -Folders @($d)); Assert ($x2.Count -eq 0) 'second pass changes nothing' } }
T 'RT03' 'FTK Imager libraries load using only their own folder and System32 (works without the Visual C++ 2010 redistributable installed)' { $f = Get-As4Tool 'ftkimager'; if (-not $f.Path) { 'BLOCKED: FTK Imager not bundled' } else {
    [void](Repair-As4ToolRuntimes -Folders @((Split-Path $f.Path))); $bad = @(); foreach ($n in 'adencrypt.dll', 'adefs.dll', 'ad_log.dll') { $h = [RtT.N]::LoadLibraryEx((Join-Path (Split-Path $f.Path) $n), [IntPtr]::Zero, 0x100 -bor 0x800); if ($h -eq [IntPtr]::Zero) { $bad += "$n error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" } else { [void][RtT.N]::FreeLibrary($h) } }
    Assert (-not $bad.Count) ($bad -join '; ') } }
T 'RT04' 'Chainsaw and YARA have vcruntime140.dll beside them after repair' { $miss = @(); foreach ($id in 'chainsaw', 'yara') { $t = Get-As4Tool $id; if ($t.Path) { [void](Repair-As4ToolRuntimes -Folders @((Split-Path $t.Path))); if (-not (Test-Path (Join-Path (Split-Path $t.Path) 'vcruntime140.dll'))) { $miss += $id } } }; Assert (-not $miss.Count) ($miss -join ', ') }
T 'LH01' 'Live inventory reads processes, connections, services, tasks, accounts and posture without changing anything' {
    $inv = Get-LhInventory
    Assert (@($inv.Processes).Count -gt 10) 'processes'; Assert (@($inv.Services).Count -gt 10) 'services'; Assert (@($inv.Connections).Count -ge 1) 'connections'; Assert (@($inv.Users).Count -ge 1) 'users'
    Assert ($inv.Posture) 'posture'; Assert (@($inv.LogChannels).Count -ge 5) 'log channels'
    "$(@($inv.Processes).Count) processes, $(@($inv.Services).Count) services, $(@($inv.Tasks).Count) tasks; unreadable parts: $(@($inv.Errors).Count)"
}
T 'LH02' 'Process rules: wrong folder and parent for a core process, imitation names, Office spawning an encoded PowerShell, temp-folder program' {
    $by = @{}; $mk = { param($id, $ppid, $name, $path, $cmd) [pscustomobject]@{ ProcessId = $id; ParentProcessId = $ppid; Name = $name; ExecutablePath = $path; CommandLine = $cmd; Created = '2026-01-01T10:00:00.0000000Z' } }
    $list = @( (& $mk 900 4 'services.exe' 'C:\Windows\System32\services.exe' ''), (& $mk 901 900 'svchost.exe' 'C:\Users\Public\svchost.exe' ''), (& $mk 902 900 'svchost.exe' 'C:\Windows\System32\svchost.exe' '-k x'), (& $mk 903 900 'scvhost.exe' 'C:\Users\Public\scvhost.exe' ''),
        (& $mk 904 4 'WINWORD.EXE' 'C:\Program Files\Microsoft Office\WINWORD.EXE' ''), (& $mk 905 904 'powershell.exe' 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' 'powershell -nop -w hidden -enc SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABOAGUAdAAuAFcAZQBiAEMAbABpAGUAbgB0ACkA'),
        (& $mk 906 4 'mimikatz.exe' 'C:\Users\Public\mimikatz.exe' 'mimikatz.exe sekurlsa::logonpasswords') )
    foreach ($p in $list) { $by[[int]$p.ProcessId] = $p }
    $all = @(); foreach ($p in $list) { $all += @(Test-LhProcess $p $by $null) }
    $t = @($all | ForEach-Object { $_.Title })
    foreach ($want in 'Windows system process running from the wrong folder', 'Windows system process with an unexpected parent', 'Program name looks like a Windows process', 'Office and reader programs started a shell or script program', 'PowerShell with an encoded command', 'Credential theft tool keywords') { Assert ($t -contains $want) "missing: $want (got: $($t -join '; '))" }
    Assert (@($all | Where-Object { $_.ProcessId -eq 902 }).Count -eq 0) 'a normal svchost.exe must not be flagged'
    "$($all.Count) leads raised on 7 synthetic processes"
}
T 'LH03' 'Verdict scale: nothing is green, one strong lead is at least orange, many are red' {
    $none = Get-LhVerdict @(); Assert ($none.Color -eq 'green' -and $none.Score -eq 0) 'empty is green'
    $one = Get-LhVerdict @(New-LhFinding 'high' 'x' 'T1' 'd'); Assert ($one.Color -in 'orange', 'red', 'darkred') "one high: $($one.Color)"
    $many = Get-LhVerdict @(1..6 | ForEach-Object { New-LhFinding 'high' 'x' "T$_" 'd' }); Assert ($many.Color -in 'red', 'darkred') "six high: $($many.Color)"
    $info = Get-LhVerdict @(New-LhFinding 'info' 'x' 'I' 'd'); Assert ($info.Color -eq 'green') 'info only stays green'
}
T 'LH04' 'Live Hunt end to end: case files, report without external links, hashes recorded, AS4 does not flag itself' {
    $r = Invoke-LiveHunt -SkipFiles
    Assert ($r.Status -eq 'OK') "status $($r.Status): $($r.Notes -join ' ')"
    foreach ($k in 'Html', 'Text', 'Csv', 'Json', 'Inventory') { Assert (Test-Path -LiteralPath $r.Files[$k]) "missing $k" }
    $h = Get-Content -LiteralPath $r.Files.Html -Raw; Assert ($h -notmatch '(src|href)\s*=\s*"https?://') 'external link in report'; Assert ($h -match 'Process tree') 'process tree'
    $led = Import-Csv (Join-Path $global:Case.Dir '00_Metadata\hashes.csv'); Assert (@($led | Where-Object { $_.RelativePath -like '*hunt_inventory*' -and $_.Kind -eq 'raw' }).Count -eq 1) 'inventory not in ledger as raw'; Assert (@($led | Where-Object { $_.RelativePath -like '*LiveHunt_*html' -and $_.Kind -eq 'derived' }).Count -eq 1) 'report not in ledger as derived'
    Assert (@($r.Findings | Where-Object { $_.ProcessId -and [int]$_.ProcessId -eq $PID }).Count -eq 0) 'AS4 flagged itself'
    "verdict $($r.Verdict.Verdict), score $($r.Verdict.Score), $(@($r.Findings).Count) items"
}
T 'LW01' 'Live Watch sees a program started outside AS4 and writes events and a report' {
    $null = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = 'cmd.exe /c ping -n 6 127.0.0.1 > nul' } -ErrorAction SilentlyContinue
    $w = Invoke-LiveWatch -Seconds 14 -IntervalSec 2
    Assert ($w.Status -eq 'OK') "status $($w.Status)"; Assert (Test-Path -LiteralPath $w.Files.Csv) 'events csv'; Assert (Test-Path -LiteralPath $w.Files.Html) 'html'
    "$(@($w.Events).Count) events"
}
T 'SN01' 'Snapshot and compare: added, removed and changed items are found, script-host autostart is called out, nothing on the machine is touched' {
    $a = New-As4Snapshot -Label a; Assert ($a.Status -eq 'OK' -and (Test-Path $a.Path)) 'snapshot a'
    $j = Get-Content -LiteralPath $a.Path -Raw | ConvertFrom-Json
    $j.RunKeys = @($j.RunKeys) + [pscustomobject]@{ Key = 'HKCU:\Test'; Name = 'Updater'; Value = 'powershell.exe -w hidden -enc AAAA' }
    $j.Services = @($j.Services | Select-Object -Skip 1)
    $j.Users = @($j.Users) + [pscustomobject]@{ Name = 'backdoor$'; Enabled = $true; PasswordRequired = $false; Sid = 'S-1-5-21-1-2-3-1009'; LastLogon = '' }
    $b = Join-Path (Split-Path $a.Path) 'snapshot_synthetic_b.json'; Write-As4File $b ($j | ConvertTo-Json -Depth 6)
    $c = Invoke-As4SnapshotCompare -Before $a.Path -After $b
    Assert ($c.Status -eq 'OK') 'compare'; $rows = @($c.Rows)
    Assert (@($rows | Where-Object { $_.Category -eq 'Autostart (registry)' -and $_.Change -eq 'Added' -and $_.Lead }).Count -eq 1) 'added Run key with lead'
    Assert (@($rows | Where-Object { $_.Category -eq 'Services' -and $_.Change -eq 'Removed' }).Count -eq 1) 'removed service'
    Assert (@($rows | Where-Object { $_.Category -eq 'Local users' -and $_.Change -eq 'Added' }).Count -eq 1) 'added user'
    Assert (Test-Path -LiteralPath $c.Html) 'html'
}
T 'SC01' 'Every First Response scenario resolves to real tasks, artifact groups and event logs (no missing ids)' {
    $n = 0; foreach ($s in Get-As4Scenarios) { $pl = Get-As4ScenarioPlan $s; Assert (@($pl.Missing).Count -eq 0) "$($s.Id) missing: $($pl.Missing -join ',')"; Assert ($pl.Steps -ge 5) "$($s.Id) too few steps"; $n++ }
    Assert ($n -ge 6) "only $n scenarios"; "$n scenarios"
}
T 'SC02' 'First Response runs a scenario in order and ends with the Live Hunt and a case report' {
    $r = Invoke-As4Scenario -Id first5 -OnProgress { param($i, $n, $t) }
    Assert ($r.Hunt -and $r.Hunt.Verdict) 'hunt'; Assert ($r.Report -and (Test-Path -LiteralPath $r.Report.Html)) 'report'; Assert (@($r.Results | Where-Object Name -eq 'Snapshot').Count -eq 1) 'snapshot'
    $bad = @($r.Results | Where-Object { $_.Status -in 'FAILED', 'TIMEOUT' -and $_.TaskId -notin 'query_user' }); Assert ($bad.Count -eq 0) (($bad | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ', ')
    "$(@($r.Results).Count) steps"
}
T 'PK01' 'Notes and evidence package: custody record, checksum list, zip hash, verify passes and detects tampering' {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $nf = Add-As4Note 'Self-test note: machine seen powered on at 10:00.'; Assert (Test-Path -LiteralPath $nf) 'note file'; Assert (@(Get-As4Notes).Count -ge 1) 'notes list'
    $k = New-As4EvidencePackage -Examiner 'Self Test' -Fast; Assert ($k.Status -eq 'OK' -and (Test-Path -LiteralPath $k.Path)) "package: $($k.Notes -join ' ')"; Assert (Test-Path -LiteralPath "$($k.Path).sha256") 'sidecar'
    $z = [IO.Compression.ZipFile]::OpenRead($k.Path); $names = @($z.Entries | ForEach-Object { $_.FullName }); $z.Dispose()
    foreach ($want in 'CHAIN_OF_CUSTODY.txt', 'PACKAGE_SHA256SUMS.txt', 'README.txt') { Assert ($names -contains $want) "zip lacks $want" }
    Assert (@($names | Where-Object { $_ -match '\\' }).Count -eq 0) 'backslash in zip entry names'
    $v = @(Test-As4EvidencePackage $k.Path); Assert (@($v | Where-Object Status -ne 'OK').Count -eq 0) (($v | Where-Object Status -ne 'OK' | Select-Object -First 3 | ForEach-Object { "$($_.Status) $($_.Item)" }) -join ', ')
    $bad = Join-Path (Split-Path $k.Path) 'tampered.zip'; Copy-Item -LiteralPath $k.Path $bad; Copy-Item -LiteralPath "$($k.Path).sha256" "$bad.sha256"
    $zu = [IO.Compression.ZipFile]::Open($bad, 'Update'); $en = $zu.Entries | Where-Object { $_.FullName -like '*/00_Metadata/case.json' } | Select-Object -First 1; $w = New-Object IO.StreamWriter($en.Open()); $w.Write('{"tampered":true}'); $w.Dispose(); $zu.Dispose()
    $v2 = @(Test-As4EvidencePackage $bad); Assert (@($v2 | Where-Object Status -eq 'MISMATCH').Count -ge 1) 'tampering not detected'
    Remove-Item -LiteralPath $bad, "$bad.sha256" -Force
    "$(@($v).Count) checks passed; tampering detected"
}
T 'SE01' 'AS4 leaves its own footprint out: matches on its folder, scripts and bundled tools are dropped from Quick Scan, Hayabusa findings, Live Hunt and Prefetch; ordinary activity is kept' {
    Assert (Test-As4SelfText "C:\x\cmd.exe /c $($global:P.Root)\tools\Hayabusa\hayabusa.exe csv-timeline") 'root path'; Assert (Test-As4SelfText 'ScriptBlock: function Get-LhIndicators {') 'marker'; Assert (-not (Test-As4SelfText 'powershell -enc AAAA from C:\Users\x\Downloads\evil.ps1')) 'ordinary text must stay'
    $mk = { param($t, $d) [pscustomobject]@{ Timestamp = '2026-01-01 10:00:00.000 +00:00'; RuleTitle = $t; Level = 'high'; Computer = 'PC'; Channel = 'Security'; EventID = 4688; MitreTactics = 'Execution'; Details = $d; ExtraFieldInfo = '' } }
    $a = Get-QsAnalysis @((& $mk 'Suspicious PowerShell' "Cmd: powershell.exe -File $($global:P.Root)\app\Main.ps1"), (& $mk 'Suspicious PowerShell' 'Cmd: powershell.exe -enc AAAA')) $null $null
    Assert ($a.Total -eq 1) "Quick Scan kept $($a.Total) rows, expected 1"; Assert (@($a.Blind | Where-Object { $_ -match 'caused by AS4' }).Count -eq 1) 'blind-spot note'
    $inv = Get-LhInventory -Light; $names = Get-As4BundledToolNames; Assert ($names.Contains('hayabusa-4.2.0-win-x64') -or $names.Contains('hayabusa')) 'bundled names'
    $inv | Add-Member -NotePropertyName Prefetch -NotePropertyValue @([pscustomobject]@{ File = 'x'; Program = 'HAYABUSA-4.2.0-WIN-X64.EXE'; LastWriteUtc = (Get-Date).ToUniversalTime().ToString('o') }, [pscustomobject]@{ File = 'y'; Program = 'MIMIKATZ.EXE'; LastWriteUtc = (Get-Date).ToUniversalTime().ToString('o') }) -Force
    $f = @(Test-LhTools $inv); Assert (@($f | Where-Object { $_.Title -match 'mimikatz' -or $_.Title -match 'MIMIKATZ' }).Count -ge 1) 'attack tool in Prefetch kept'; Assert (@($f | Where-Object { $_.Title -match 'hayabusa' }).Count -eq 0) 'own tool ignored'
}
T 'S01' 'No download/install/remediation primitives in application code' {
    $pat = 'Invoke-WebRequest|Invoke-RestMethod|DownloadFile|DownloadString|Start-BitsTransfer|WebClient|msiexec|winget|choco|Install-Module|Install-Package|New-Service|sc\.exe\s+(create|delete)|schtasks\S*\s+/create|reg\.exe[^|]*\sadd|Stop-Process|Remove-Item\s+.*-Recurse.*C:|Clear-EventLog|wevtutil[^|]*\scl\b|Set-MpPreference|Disable-'
    $hits = Get-ChildItem $app,$tasksDir -Filter *.ps1 | Select-String -Pattern $pat | Where-Object { $_.Line -notmatch '^\s*#' -and $_.Line -notmatch 'TriageLeads|Message -match' }   # heuristic keyword lists are detection patterns, not actions
    $own = $hits | Where-Object { $_.Line -notmatch 'Remove-Item -LiteralPath \$(dest|Dst)' }   # own partial-output cleanup inside case folder
    Assert (-not $own) (($own | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', ')
}
T 'S02' 'Application contains no hardcoded drive-letter roots (except C:\ Windows artifact locations)' {
    $h = Get-ChildItem $app,$tasksDir -Filter *.ps1 | Select-String -CaseSensitive -Pattern '(?<![A-Za-z])[D-Z]:\\' | Where-Object { $_.Line -notmatch 'e\.g\.|Example|\$env' }
    Assert (-not $h) (($h | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', ')
}
Stop-As4Run
Remove-Item $synth -Recurse -Force -ErrorAction SilentlyContinue
$pass = @($R | Where-Object Result -eq 'PASS').Count; $fail = @($R | Where-Object Result -eq 'FAIL').Count; $blk = @($R | Where-Object Result -eq 'BLOCKED').Count
Write-Host "`nSUMMARY: PASS=$pass FAIL=$fail BLOCKED=$blk  (case $cid at $($global:Case.Dir))"
if ($ResultFile) {
    $md = "## Self-test run $(Get-UtcIso) UTC`n`nHost: $env:COMPUTERNAME, admin=$(Test-As4Admin), root=$Root`n`n| ID | Result | Test | Detail |`n|---|---|---|---|`n" + (($R | ForEach-Object { "| $($_.Id) | **$($_.Result)** | $($_.Test) | $(($_.Detail -replace '\|','/') -replace '\r?\n',' ') |" }) -join "`n") + "`n`nPASS=$pass FAIL=$fail BLOCKED=$blk`n"
    [IO.File]::WriteAllText($ResultFile, $md)
}
exit $(if ($fail) { 1 } else { 0 })
