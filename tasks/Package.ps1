# AS4 IR Tool - examiner notes and the evidence package (zip + chain of custody + checksums). ASCII only.
# The package is written next to the cases (output\_packages), never inside a case, and never changes the case.

function Add-As4Note {
    param([Parameter(Mandatory)][string]$Text)
    if (-not $global:Case) { throw 'No active case.' }
    $t = $Text.Trim(); if (-not $t) { throw 'The note is empty.' }
    $dir = Join-Path (Get-CaseFolder 'Meta') 'notes'
    $f = Get-UniquePath $dir 'note' 'txt'
    Write-As4File $f ("Time (UTC): $(Get-UtcIso)`r`nExaminer: $env:USERDOMAIN\$env:USERNAME on $env:COMPUTERNAME`r`n`r`n$t`r`n")
    $keep = $global:RunId; if (-not $global:RunId) { $global:RunId = 'NOTE-' + (Get-UtcStamp) }
    Register-As4Files @($f) 'note' | Out-Null; $global:RunId = $keep
    Write-As4Log INFO "Note saved: $(Get-RelPath $f)"
    $f
}

function Get-As4Notes {
    param([string]$CaseDir)
    if (-not $CaseDir) { $CaseDir = $global:Case.Dir }
    $d = Join-Path $CaseDir '00_Metadata\notes'
    if (-not (Test-Path -LiteralPath $d)) { return @() }
    Get-ChildItem -LiteralPath $d -Filter 'note_*.txt' -File | Sort-Object Name | ForEach-Object { $c = Get-Content -LiteralPath $_.FullName -Raw; $when = ''; if ($c -match 'Time \(UTC\): (\S+)') { $when = $Matches[1] }; $body = ($c -split "(\r?\n){2}", 2)[-1].Trim(); [pscustomobject]@{ Path = $_.FullName; Time = $when; Text = $body } }
}

function New-CustodyText {
    param($CaseDir, $Meta, $Manifest, $Hashes, $Verify, $Notes, $Examiner)
    $h = Get-As4Host; $sb = New-Object Text.StringBuilder
    $runs = @($Manifest | ForEach-Object { $_.RunId } | Where-Object { $_ } | Select-Object -Unique)
    $first = ($Manifest | ForEach-Object { $_.StartUtc } | Where-Object { $_ } | Sort-Object | Select-Object -First 1); $last = ($Manifest | ForEach-Object { $_.EndUtc } | Where-Object { $_ } | Sort-Object | Select-Object -Last 1)
    $st = @($Manifest | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join '  '
    [void]$sb.AppendLine('CHAIN OF CUSTODY AND COLLECTION RECORD'); [void]$sb.AppendLine('======================================'); [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Case name            : $($Meta.CaseName)"); [void]$sb.AppendLine("Case created (UTC)   : $($Meta.CreatedUtc)"); [void]$sb.AppendLine("Package created (UTC): $(Get-UtcIso)")
    [void]$sb.AppendLine("Examiner             : $Examiner"); [void]$sb.AppendLine("Tool                 : AS4 IR Tool $($global:AS4Version)")
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('SOURCE (the machine AS4 ran on)')
    [void]$sb.AppendLine("  Computer           : $($h.Computer)"); [void]$sb.AppendLine("  Operating system   : $($h.OS) $($h.Arch)"); [void]$sb.AppendLine("  Time zone          : $([TimeZoneInfo]::Local.Id)"); [void]$sb.AppendLine("  Account used       : $($h.User)  (administrator: $($h.Admin))")
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('COLLECTION')
    [void]$sb.AppendLine("  First action (UTC) : $first"); [void]$sb.AppendLine("  Last action (UTC)  : $last"); [void]$sb.AppendLine("  Runs               : $($runs.Count)"); [void]$sb.AppendLine("  Operations         : $(@($Manifest).Count)   ($st)"); [void]$sb.AppendLine("  Files in the ledger: $(@($Hashes).Count)")
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('INTEGRITY CHECK MADE WHEN THE PACKAGE WAS BUILT')
    [void]$sb.AppendLine("  Checked: $($Verify.Total)   OK: $($Verify.OK)   Changed: $($Verify.Changed)   Missing: $($Verify.Missing)")
    if ($Verify.Changed -or $Verify.Missing) { [void]$sb.AppendLine('  WARNING: some files no longer match the hash recorded when they were collected. See the list in the case folder.') }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('WHAT AS4 DID AND DID NOT DO')
    foreach ($l in 'It only read the machine. It did not install software, delete, stop, quarantine or change anything on it.', 'Running any tool leaves traces (new processes, Prefetch entries, event log records). Reading files can change last-access times.', 'Everything saved was hashed with SHA-256 at the moment it was written (hashes.csv). Raw evidence and derived analysis are kept apart.', 'Rule matches and scores are leads for a person to confirm, not findings of fact.') { [void]$sb.AppendLine("  - $l") }
    if (@($Notes).Count) { [void]$sb.AppendLine(''); [void]$sb.AppendLine('EXAMINER NOTES'); foreach ($n in $Notes) { [void]$sb.AppendLine("  [$($n.Time)] $($n.Text -replace '\r?\n', ' ')") } }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('TRANSFER'); [void]$sb.AppendLine('  Released by (name, signature, date, time): ______________________________________________'); [void]$sb.AppendLine('  Received by (name, signature, date, time): ______________________________________________'); [void]$sb.AppendLine('  Storage location / reason for transfer   : ______________________________________________')
    $sb.ToString()
}

function New-As4EvidencePackage {
    param([string]$Examiner, [scriptblock]$OnProgress, [switch]$Fast)
    if (-not $global:Case) { throw 'No active case.' }
    if (-not $Examiner) { $Examiner = "$env:USERDOMAIN\$env:USERNAME" }
    $caseDir = $global:Case.Dir; $caseId = $global:Case.Id
    $e = New-As4Entry 'package' 'Evidence package' $global:CaseFolders.Rep
    Start-As4Run 'package' | Out-Null; $der = @(); $zipPath = $null
    try {
        if ($OnProgress) { & $OnProgress 0 1 'Checking the hashes of every file first' }
        $led = Join-Path $caseDir '00_Metadata\hashes.csv'; $hashes = @(); if (Test-Path -LiteralPath $led) { $hashes = @(Import-Csv -LiteralPath $led) }
        $chk = @(); if ($hashes.Count) { $chk = @(Test-As4Hashes $caseDir) }
        $verify = [pscustomobject]@{ Total = $chk.Count; OK = @($chk | Where-Object Status -eq 'OK').Count; Changed = @($chk | Where-Object Status -eq 'MISMATCH').Count; Missing = @($chk | Where-Object Status -eq 'MISSING').Count }
        $meta = Get-Content -LiteralPath (Join-Path $caseDir '00_Metadata\case.json') -Raw | ConvertFrom-Json
        $man = @(Get-As4Manifest $caseDir); $notes = @(Get-As4Notes $caseDir)
        $cust = New-CustodyText $caseDir $meta $man $hashes $verify $notes $Examiner
        $rep = Get-CaseFolder 'Rep'
        $ct = Get-UniquePath $rep 'chain_of_custody' 'txt'; Write-As4File $ct $cust; $der += $ct
        $pk = Join-Path $global:P.Output '_packages'; New-Item -ItemType Directory -Path $pk -Force | Out-Null
        $files = @(Get-ChildItem -LiteralPath $caseDir -Recurse -File -Force -ErrorAction SilentlyContinue)
        $bytes = ($files | Measure-Object Length -Sum).Sum; $free = Get-DiskFreeBytes $pk
        if ($free -and $bytes -gt $free) { throw "Not enough free space: the case is $([math]::Round($bytes/1MB)) MB and the drive has $([math]::Round($free/1MB)) MB free." }
        $zipPath = Get-UniquePath $pk ($caseId + '_evidence') 'zip'
        Add-Type -AssemblyName System.IO.Compression
        $fs = [IO.File]::Create($zipPath); $arc = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        $sums = New-Object Text.StringBuilder; $buf = New-Object byte[] 1048576; $i = 0; $levelFast = [IO.Compression.CompressionLevel]::Fastest
        $addFile = {
            param($path, $entryName, $lvl)
            $en = $arc.CreateEntry($entryName, $lvl); try { $en.LastWriteTime = (Get-Item -LiteralPath $path).LastWriteTime } catch {}
            $sha = [Security.Cryptography.SHA256]::Create(); $src = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)); $dst = $en.Open()
            try { while (($n = $src.Read($buf, 0, $buf.Length)) -gt 0) { $dst.Write($buf, 0, $n); [void]$sha.TransformBlock($buf, 0, $n, $null, 0) }; [void]$sha.TransformFinalBlock($buf, 0, 0) } finally { $dst.Dispose(); $src.Dispose() }
            ($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join '' }
        foreach ($f in $files) {
            if ($global:Cancel) { throw [OperationCanceledException]::new('cancelled') }
            $i++; if ($OnProgress -and ($i % 20 -eq 1)) { & $OnProgress $i $files.Count $f.Name }; if ($global:UiPump) { & $global:UiPump }
            $rel = $f.FullName.Substring($caseDir.TrimEnd('\').Length + 1).Replace('\', '/'); $entry = "$caseId/$rel"
            $lvl = $(if ($Fast -or $f.Length -gt 200MB -or $f.Extension -in '.zip', '.raw', '.mem', '.dmp', '.aff4') { [IO.Compression.CompressionLevel]::NoCompression } else { $levelFast })
            try { $h = & $addFile $f.FullName $entry $lvl; [void]$sums.AppendLine("$h  $entry") } catch { Write-As4Log WARN "Not packaged: $($f.FullName): $($_.Exception.Message)" }
        }
        # the custody record and checksum list sit at the top of the zip
        # staging stays inside the AS4 folder, never in the endpoint's temp
        $tmp = Join-Path $pk ('_work_' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp -Force | Out-Null
        try {
            $ctxt = Join-Path $tmp 'CHAIN_OF_CUSTODY.txt'; [IO.File]::WriteAllText($ctxt, $cust, $global:Utf8); [void](& $addFile $ctxt 'CHAIN_OF_CUSTODY.txt' $levelFast)
            $rd = Join-Path $tmp 'README.txt'; [IO.File]::WriteAllText($rd, "Evidence package for case '$caseId'.`r`n`r`nPACKAGE_SHA256SUMS.txt lists the SHA-256 of every file in this zip. Verify it with AS4 (Evidence Package > Verify) or with:  certutil -hashfile <file> SHA256`r`nCHAIN_OF_CUSTODY.txt records where, when and how the data was collected.`r`n", $global:Utf8); [void](& $addFile $rd 'README.txt' $levelFast)
            $sf = Join-Path $tmp 'PACKAGE_SHA256SUMS.txt'; [IO.File]::WriteAllText($sf, $sums.ToString(), $global:Utf8); [void](& $addFile $sf 'PACKAGE_SHA256SUMS.txt' $levelFast)
        } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        $arc.Dispose(); $fs.Dispose()
        $zh = Get-As4Sha256 $zipPath; Write-As4File "$zipPath.sha256" "$zh  $(Split-Path $zipPath -Leaf)`r`n"
        $e.Status = 'OK'; $e.Notes += "Package: $zipPath ($([math]::Round((Get-Item $zipPath).Length/1MB,1)) MB, $($files.Count) files). SHA-256 $zh. Integrity before packaging: $($verify.OK) OK, $($verify.Changed) changed, $($verify.Missing) missing."
        $e.Command = 'powershell (in-process)'
        if ($verify.Changed -or $verify.Missing) { $e.Warnings += 'Some files did not match their recorded hash when the package was built.' }
    } catch [OperationCanceledException] { $e.Status = 'CANCELLED'; if ($zipPath -and (Test-Path -LiteralPath $zipPath)) { try { $arc.Dispose(); $fs.Dispose() } catch {}; Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue; $zipPath = $null } }
    catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message; Write-As4Log ERROR "Package: $($_.Exception.Message)"; if ($zipPath -and (Test-Path -LiteralPath $zipPath)) { try { $arc.Dispose(); $fs.Dispose() } catch {}; Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue; $zipPath = $null } }
    $out = Complete-As4Entry $e @() 'derived'
    if ($der.Count) { Register-As4Files $der 'derived' | Out-Null }
    Stop-As4Run
    [pscustomobject]@{ Status = $out.Status; Notes = @($out.Notes); Path = $zipPath; Custody = $(if ($der.Count) { $der[0] } else { $null }) }
}

function Test-As4EvidencePackage {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Not found: $Path" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $rows = New-Object Collections.ArrayList
    $side = "$Path.sha256"
    if (Test-Path -LiteralPath $side) { $exp = ((Get-Content -LiteralPath $side -Raw).Trim() -split '\s+')[0]; $act = Get-As4Sha256 $Path; [void]$rows.Add([pscustomobject]@{ Status = $(if ($exp -eq $act) { 'OK' } else { 'MISMATCH' }); Item = '(the zip file itself)'; Expected = $exp; Actual = $act }) }
    else { [void]$rows.Add([pscustomobject]@{ Status = 'NO_SIDECAR'; Item = '(the zip file itself)'; Expected = ''; Actual = (Get-As4Sha256 $Path) }) }
    $z = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $sumE = $z.Entries | Where-Object FullName -eq 'PACKAGE_SHA256SUMS.txt' | Select-Object -First 1
        if (-not $sumE) { [void]$rows.Add([pscustomobject]@{ Status = 'MISSING'; Item = 'PACKAGE_SHA256SUMS.txt'; Expected = ''; Actual = '' }) }
        else {
            $sr = New-Object IO.StreamReader($sumE.Open()); $txt = $sr.ReadToEnd(); $sr.Dispose(); $listed = @{}
            foreach ($l in ($txt -split "\r?\n")) { if ($l -match '^([0-9a-f]{64})  (.+)$') { $listed[$Matches[2]] = $Matches[1] } }
            foreach ($k in $listed.Keys) { $en = $z.GetEntry($k); if (-not $en) { [void]$rows.Add([pscustomobject]@{ Status = 'MISSING'; Item = $k; Expected = $listed[$k]; Actual = '' }); continue }
                $sha = [Security.Cryptography.SHA256]::Create(); $st = $en.Open(); try { $h = ($sha.ComputeHash($st) | ForEach-Object { $_.ToString('x2') }) -join '' } finally { $st.Dispose(); $sha.Dispose() }
                [void]$rows.Add([pscustomobject]@{ Status = $(if ($h -eq $listed[$k]) { 'OK' } else { 'MISMATCH' }); Item = $k; Expected = $listed[$k]; Actual = $h }) }
            $extra = @($z.Entries | Where-Object { $_.FullName -notmatch '/$' -and -not $listed.ContainsKey($_.FullName) -and $_.FullName -notin 'PACKAGE_SHA256SUMS.txt', 'CHAIN_OF_CUSTODY.txt', 'README.txt' })
            foreach ($x in $extra) { [void]$rows.Add([pscustomobject]@{ Status = 'NOT_LISTED'; Item = $x.FullName; Expected = ''; Actual = '' }) }
        }
    } finally { $z.Dispose() }
    @($rows)
}

function Get-As4Packages {
    $pk = Join-Path $global:P.Output '_packages'
    if (-not (Test-Path -LiteralPath $pk)) { return @() }
    Get-ChildItem -LiteralPath $pk -Filter '*.zip' -File | Sort-Object LastWriteTime -Descending
}
