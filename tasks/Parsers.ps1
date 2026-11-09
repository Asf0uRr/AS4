# AS4 IR Tool - Parse what was collected: Prefetch, Amcache, Shimcache, LNK, Jump Lists, Recycle Bin, SRUM, MFT, event logs. ASCII only.
# Runs the bundled Zimmerman command-line parsers on files already inside the case (never on the live system) and saves CSV into 15_Parsed.

function Find-As4CaseFiles {
    # returns paths inside the case whose file name matches; used to feed the parsers
    param([string[]]$Names, [switch]$Dirs)
    $root = $global:Case.Dir; $skip = '\\(15_Parsed|12_Reports|13_Collection_Logs|14_Live_Analysis|00_Metadata)\\'
    $out = New-Object Collections.ArrayList
    foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)) { if ($f.FullName -match $skip) { continue }; foreach ($n in $Names) { if ($f.Name -like $n) { [void]$out.Add($f); break } } }
    if ($Dirs) { return @($out | ForEach-Object { $_.DirectoryName } | Select-Object -Unique) }
    @($out | ForEach-Object { $_.FullName })
}

function Get-As4Parsers {
    @(
    @{ Id = 'prefetch'; Name = 'Prefetch (what ran, how often, when)'; Tool = 'ez-pecmd'; Admin = $false
       Find = { Find-As4CaseFiles @('*.pf') -Dirs }; Args = { param($in, $out) @('-d', $in, '--csv', $out, '--csvf', 'prefetch.csv', '-q') } }
    @{ Id = 'amcache'; Name = 'Amcache (programs that ran, with hashes)'; Tool = 'ez-amcache'; Admin = $false
       Find = { Find-As4CaseFiles @('Amcache.hve') }; Args = { param($in, $out) @('-f', $in, '--csv', $out, '--csvf', 'amcache.csv', '-i') } }
    @{ Id = 'shimcache'; Name = 'Shimcache (programs seen by Windows)'; Tool = 'ez-appcompat'; Admin = $false
       Find = { Find-As4CaseFiles @('SYSTEM') }; Args = { param($in, $out) @('-f', $in, '--csv', $out, '--csvf', 'shimcache.csv') } }
    @{ Id = 'lnk'; Name = 'Shortcut files (files and folders opened)'; Tool = 'ez-lecmd'; Admin = $false
       Find = { Find-As4CaseFiles @('*.lnk') -Dirs }; Args = { param($in, $out) @('-d', $in, '--csv', $out, '--csvf', 'lnk.csv', '-q') } }
    @{ Id = 'jumplists'; Name = 'Jump Lists (recent items per program)'; Tool = 'ez-jlecmd'; Admin = $false
       Find = { Find-As4CaseFiles @('*.automaticDestinations-ms', '*.customDestinations-ms') -Dirs }; Args = { param($in, $out) @('-d', $in, '--csv', $out, '--csvf', 'jumplists.csv', '-q') } }
    @{ Id = 'recycle'; Name = 'Recycle Bin (deleted files)'; Tool = 'ez-rbcmd'; Admin = $false
       Find = { Find-As4CaseFiles @('$I*') -Dirs }; Args = { param($in, $out) @('-d', $in, '--csv', $out, '--csvf', 'recyclebin.csv') } }
    @{ Id = 'srum'; Name = 'SRUM (network and app usage per program)'; Tool = 'ez-srumecmd'; Admin = $false
       Find = { Find-As4CaseFiles @('SRUDB.dat') }; Args = { param($in, $out) @('-f', $in, '--csv', $out) } }
    @{ Id = 'mft'; Name = 'Master File Table'; Tool = 'ez-mftecmd'; Admin = $false
       Find = { Find-As4CaseFiles @('$MFT') }; Args = { param($in, $out) @('-f', $in, '--csv', $out, '--csvf', 'mft.csv') } }
    @{ Id = 'evtx'; Name = 'Event logs to one CSV'; Tool = 'ez-evtxecmd'; Admin = $false
       Find = { Find-As4CaseFiles @('*.evtx') -Dirs }; Args = { param($in, $out) @('-d', $in, '--csv', $out, '--csvf', 'evtx.csv') } }
    ) | ForEach-Object { [pscustomobject]$_ }
}

function Invoke-As4Parsers {
    param([string[]]$Ids, [scriptblock]$OnProgress)
    if (-not $global:Case) { throw 'No active case.' }
    Start-As4Run 'parsers' | Out-Null
    $all = @(Get-As4Parsers); if ($Ids) { $all = @($all | Where-Object { $Ids -contains $_.Id }) }
    $res = New-Object Collections.ArrayList; $i = 0
    foreach ($p in $all) {
        $i++; if ($OnProgress) { & $OnProgress $i $all.Count $p.Name }
        if ($global:Cancel) { break }
        $e = New-As4Entry ('parse_' + $p.Id) ("Parse: $($p.Name)") $global:CaseFolders.Parsed 'collected files in this case'
        $files = @()
        try {
            $t = Get-As4Tool $p.Tool
            if (-not $t -or -not $t.Path) { $e.Status = 'SKIPPED'; $e.Notes += "Parser not found in tools\ ($($p.Tool))."; [void]$res.Add((Complete-As4Entry $e @())); continue }
            if ($t.Status -eq 'PRESENT_HASH_MISMATCH') { $e.Status = 'SKIPPED'; $e.Notes += 'Hash mismatch against the manifest; not run.'; [void]$res.Add((Complete-As4Entry $e @())); continue }
            $inputs = @(& $p.Find)
            if (-not $inputs.Count) { $e.Status = 'SKIPPED'; $e.Notes += 'Nothing to parse: this case has no matching files yet (collect them first).'; [void]$res.Add((Complete-As4Entry $e @())); continue }
            $e.ToolVersion = $t.FileVersion; $e.Command = $t.Path; $okN = 0; $argLog = @()
            foreach ($in in ($inputs | Select-Object -First 4)) {
                $out = Join-Path (Get-CaseFolder 'Parsed') ($p.Id + '_' + (Get-UtcStamp)); New-Item -ItemType Directory -Path $out -Force | Out-Null
                $r = Invoke-As4Native -Exe $t.Path -Arguments (& $p.Args $in $out) -TimeoutSec 900 -WorkDir (Split-Path $t.Path)
                $argLog += $r.ArgString
                $made = @(Get-ChildItem -LiteralPath $out -Recurse -File -ErrorAction SilentlyContinue)
                if ($r.ExitCode -eq 0 -and $made.Count) { $okN++; $files += @($made | ForEach-Object { $_.FullName }) } else { $e.Warnings += "No output for $(Split-Path $in -Leaf) (exit $($r.ExitCode))." }
            }
            $e.Arguments = $argLog -join ' || '
            if ($okN) { $e.Status = 'OK'; $e.Notes += "$okN input(s) parsed, $($files.Count) file(s) written." } else { $e.Status = 'FAILED'; $e.Notes += 'The parser produced no output.' }
        } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
        [void]$res.Add((Complete-As4Entry $e $files 'derived'))
    }
    Stop-As4Run
    @($res)
}
