# AS4 IR Tool - Hayabusa (Yamato Security). ASCII only.
# Options are read from the installed Hayabusa's own help (`<command> -h`), so every option and filter of the
# bundled version is offered and nothing is invented. AS4 controls input, output location, wizard and colour.

$global:HayCache = @{}
$global:HayHidden = @('--directory', '--file', '--live-analysis', '--output', '--clobber', '--help', '--no-wizard', '--quiet', '--no-color', '--html-report')
$global:HayEnums = @{
    '--min-level' = @('informational', 'low', 'medium', 'high', 'critical'); '--exact-level' = @('informational', 'low', 'medium', 'high', 'critical')
    '--output-type' = @('csv', 'json', 'jsonl')
}
# commands AS4 exposes. update-rules (network), set-default-profile and level-tuning (change the tool's own files) are not offered.
$global:HayCommands = [ordered]@{
    'dfir-timeline'           = 'DFIR timeline: run the detection rules over the event logs'
    'search'                  = 'Search all events by keyword(s) or regular expression'
    'logon-summary'           = 'Summary of successful and failed logons'
    'eid-metrics'             = 'Event ID counts'
    'computer-metrics'        = 'Event counts per computer name'
    'log-metrics'             = 'Metadata of each event log file'
    'extract-base64'          = 'Extract and decode base64 strings from events'
    'pivot-keywords-list'     = 'Pivot keywords (users, hosts, IPs, processes) found in alerts'
    'config-critical-systems' = 'Find critical systems such as domain controllers and file servers'
    'sort-csv'                = 'Sort a Hayabusa CSV by time and remove duplicate detections'
    'list-profiles'           = 'List the output profiles'
    'expand-list'             = 'Extract expand placeholders from the rules folder'
}

function Get-HayabusaInfo {
    param([switch]$Refresh)
    if ($global:HayCache.Info -and -not $Refresh) { return $global:HayCache.Info }
    $t = Get-As4Tool 'hayabusa'
    $i = [ordered]@{ Present = $false; Path = $null; Dir = $null; Runnable = $false; Version = $null; BlockReason = $null; Rules = $null; RuleFiles = 0; Config = $null }
    if ($t -and $t.Path) {
        $i.Present = $true; $i.Path = $t.Path; $i.Dir = Split-Path $t.Path
        $rd = Join-Path $i.Dir 'rules'; if (Test-Path $rd) { $i.Rules = $rd; $i.Config = Join-Path $rd 'config'; $i.RuleFiles = @(Get-ChildItem $rd -Recurse -File -Filter *.yml -ErrorAction SilentlyContinue).Count }
        $r = Invoke-As4Native -Exe $i.Path -Arguments @('help') -TimeoutSec 30
        if ($r.Error) { $i.BlockReason = $r.Error }
        else { $i.Runnable = $true; $l = ($r.StdOut + $r.StdErr) -split "`n" | Where-Object { $_ -match 'Hayabusa v' } | Select-Object -First 1; if ($l) { $i.Version = ($l -replace '\x1b\[[0-9;]*m', '').Trim() } }
    }
    $global:HayCache.Info = [pscustomobject]$i
    $global:HayCache.Info
}

function Remove-AnsiCodes { param([string]$s) ($s -replace '\x1b\[[0-9;]*[A-Za-z]', '') -replace '\[0m|\[38;2;\d+;\d+;\d+m', '' }

function Get-HayabusaSpec {
    # Parses `hayabusa <command> -h`: sections and options (short, long, value name, multi-value, description).
    param([Parameter(Mandatory)][string]$Command)
    if ($global:HayCache.ContainsKey("spec:$Command")) { return $global:HayCache["spec:$Command"] }
    $hi = Get-HayabusaInfo; if (-not $hi.Runnable) { return $null }
    $r = Invoke-As4Native -Exe $hi.Path -Arguments @($Command, '-h', '-K') -TimeoutSec 30 -WorkDir $hi.Dir
    $txt = Remove-AnsiCodes ($r.StdOut + "`n" + $r.StdErr)
    $sections = New-Object Collections.ArrayList; $cur = $null; $usage = ''
    foreach ($line in ($txt -split "`r?`n")) {
        if ($line -match '^\s+hayabusa(\.exe)?\s+' -and -not $usage) { $usage = $line.Trim(); continue }
        if ($line -match '^([A-Z][A-Za-z ]+):\s*$') { $cur = [pscustomobject]@{ Name = $Matches[1]; Options = New-Object Collections.ArrayList }; [void]$sections.Add($cur); continue }
        if ($cur -and $line -match '^\s+(?:(-[A-Za-z]),\s+)?(--[A-Za-z0-9-]+)(?:\s+<([^>]+)>)?\s{2,}(.*)$') {
            $v = $Matches[3]; $multi = $false; if ($v -and $v.EndsWith('...')) { $multi = $true; $v = $v.Substring(0, $v.Length - 3) }
            [void]$cur.Options.Add([pscustomobject]@{ Short = $Matches[1]; Long = $Matches[2]; Value = $v; Multi = $multi; Desc = $Matches[4].Trim() })
        }
    }
    $spec = [pscustomobject]@{ Command = $Command; Usage = $usage; Sections = $sections; Help = $txt }
    $global:HayCache["spec:$Command"] = $spec
    $spec
}

function Get-HayabusaProfiles {
    $hi = Get-HayabusaInfo; if (-not $hi.Runnable) { return @() }
    $r = Invoke-As4Native -Exe $hi.Path -Arguments @('list-profiles', '-q', '-K') -TimeoutSec 30 -WorkDir $hi.Dir
    @((Remove-AnsiCodes $r.StdOut) -split "`r?`n" | ForEach-Object { if ($_ -match '^- ([a-z0-9-]+):') { $Matches[1] } })
}

function Get-HayabusaPresets {
    foreach ($f in (Get-ChildItem $global:P.Profiles -Filter 'hayabusa_*.json' -ErrorAction SilentlyContinue | Sort-Object Name)) { Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json }
}

function Build-HayabusaArgs {
    # Input: @{ Kind = 'directory'|'file'|'live'|'none'; Path = ... }. Options: long name (no dashes) -> $true | value | array.
    param([string]$Command, [hashtable]$InSpec, [hashtable]$Options, [string]$OutDir)
    $spec = Get-HayabusaSpec $Command; if (-not $spec) { throw 'Hayabusa cannot run on this machine.' }
    $all = @(); foreach ($s in $spec.Sections) { $all += @($s.Options) }
    $has = @{}; foreach ($o in $all) { $has[$o.Long] = $o }
    $a = @($Command); $notes = @(); $outFiles = @()
    switch ($InSpec.Kind) {
        'directory' { if (-not (Test-Path -LiteralPath $InSpec.Path -PathType Container)) { throw "Folder not found: $($InSpec.Path)" }; $a += @('--directory', $InSpec.Path) }
        'file' { if (-not (Test-Path -LiteralPath $InSpec.Path -PathType Leaf)) { throw "File not found: $($InSpec.Path)" }; $a += @('--file', $InSpec.Path) }
        'live' { if (-not $has.ContainsKey('--live-analysis')) { throw "$Command does not support live analysis." }; $a += '--live-analysis' }
        default { if ($has.ContainsKey('--directory') -or $has.ContainsKey('--file')) { throw 'Select an input: folder, file or live system.' } }
    }
    # user options, validated against the real option list
    foreach ($k in ($Options.Keys | Sort-Object)) {
        $long = "--$k"; $v = $Options[$k]
        if (-not $has.ContainsKey($long)) { $notes += "$long is not an option of $Command in this Hayabusa version; skipped"; continue }
        if ($global:HayHidden -contains $long -and $long -ne '--html-report') { continue }
        $o = $has[$long]
        if ($long -eq '--html-report') { if ($v) { $f = Join-Path $OutDir 'report.html'; $a += @('--html-report', $f); $outFiles += $f }; continue }
        if (-not $o.Value) { if ($v -eq $true) { $a += $long }; continue }
        $vals = @($v | Where-Object { $_ -ne $null -and "$_".Trim() -ne '' })
        if (-not $vals.Count) { continue }
        if ($global:HayEnums.ContainsKey($long)) { foreach ($x in $vals) { if ($global:HayEnums[$long] -notcontains "$x") { throw "$long must be one of: $($global:HayEnums[$long] -join ', ')" } } }
        if ($long -in '--time-offset') { if ("$($vals[0])" -notmatch '^\d+[yMdhm]$') { throw '--time-offset must look like 30d, 24h, 30m, 3M or 1y' } }
        if ($long -in '--threads') { if ("$($vals[0])" -notmatch '^\d+$') { throw '--threads must be a number' } }
        if ($long -in '--timeline-start', '--timeline-end') { if ("$($vals[0])" -notmatch '^\d{4}-\d{2}-\d{2}( \d{2}:\d{2}:\d{2}( [+-]\d{2}:\d{2})?)?$') { throw "$long must look like ""2026-10-01 00:00:00 +00:00""" } }
        if ($o.Multi) { $parts = @(foreach ($x in $vals) { ("$x") -split '[,;\s]+' | Where-Object { $_ } }); $a += @($long, ($parts -join ',')) }   # Hayabusa wants one comma-separated value
        else { $a += @($long, "$($vals[0])") }
    }
    # these options need sorted results; Hayabusa refuses them without --sort
    if ($has.ContainsKey('--sort') -and -not $Options['sort'] -and ($Options['remove-duplicate-data'] -or $Options['remove-duplicate-detections'] -or $Options['visualize-timeline'])) { $a += '--sort'; $notes += '--sort added automatically (required by the duplicate-removal and timeline-visualisation options)' }
    # gentle on the endpoint: use half of the CPU cores unless the analyst chose a number
    if ($has.ContainsKey('--threads') -and -not $Options.ContainsKey('threads')) { $cores = [Environment]::ProcessorCount; $a += @('--threads', ([string][math]::Max(1, [int][math]::Floor($cores / 2)))) }
    # fixed by AS4
    if ($has.ContainsKey('--no-wizard')) { $a += '--no-wizard' }
    if ($has.ContainsKey('--quiet')) { $a += '--quiet' }
    if ($has.ContainsKey('--no-color')) { $a += '--no-color' }
    if ($has.ContainsKey('--rules') -and $global:HayCache.Info.Rules -and -not $Options.ContainsKey('rules')) { $a += @('--rules', $global:HayCache.Info.Rules) }
    if ($has.ContainsKey('--rules-config') -and $global:HayCache.Info.Config -and -not $Options.ContainsKey('rules-config')) { $a += @('--rules-config', $global:HayCache.Info.Config) }
    # output
    $ot = if ($Options['output-type']) { "$($Options['output-type'])" } else { 'csv' }
    switch ($Command) {
        'dfir-timeline' { $f = Join-Path $OutDir "timeline.$ot"; $a += @('--output', $f); $outFiles += $f }
        'search' {
            if (-not $Options['keyword'] -and -not $Options['regex']) { throw 'Search needs keyword(s) or a regular expression.' }
            if ($Options['json-output']) { $f = Join-Path $OutDir 'search.json' } elseif ($Options['jsonl-output']) { $f = Join-Path $OutDir 'search.jsonl' } else { $f = Join-Path $OutDir 'search.csv' }
            $a += @('--output', $f); $outFiles += $f }
        'logon-summary' { $a += @('--output', (Join-Path $OutDir 'logon-summary')) }
        'pivot-keywords-list' { $a += @('--output', (Join-Path $OutDir 'pivot')) }
        { $_ -in 'eid-metrics', 'computer-metrics', 'log-metrics', 'extract-base64' } { $f = Join-Path $OutDir "$Command.csv"; $a += @('--output', $f); $outFiles += $f }
        'sort-csv' { $f = Join-Path $OutDir 'sorted.csv'; $a += @('--output', $f); $outFiles += $f }
    }
    [pscustomobject]@{ Args = $a; Notes = $notes; Expected = $outFiles; NeedsToolDir = (-not $has.ContainsKey('--rules')) }
}

function Invoke-Hayabusa {
    param([Parameter(Mandatory)][string]$Command, [hashtable]$InSpec = @{ Kind = 'none' }, [hashtable]$Options = @{}, [string]$PostFilter, [string]$Id, [string]$Title)
    $hi = Get-HayabusaInfo -Refresh
    $e = New-As4Entry $(if ($Id) { "hayabusa_$Id" } else { "hayabusa_$Command" }) $(if ($Title) { "Hayabusa: $Title" } else { "Hayabusa $Command" }) $global:CaseFolders.Hay 'selected event logs'
    Start-As4Run "hayabusa-$Command" | Out-Null; $files = @()
    try {
        if (-not $hi.Present) { $e.Status = 'SKIPPED'; $e.Notes += 'Hayabusa was not found in tools\Hayabusa.'; return (Complete-As4Entry $e @()) }
        if (-not $hi.Runnable) { $e.Status = 'SKIPPED'; $e.Notes += "Hayabusa cannot run: $($hi.BlockReason)"; return (Complete-As4Entry $e @()) }
        if (-not $global:HayCommands.Contains($Command)) { throw "Unsupported command '$Command'." }
        if ($InSpec.Kind -eq 'live' -and -not (Test-As4Admin)) { $e.Warnings += 'Live analysis without administrator: some logs (Security) cannot be read.' }
        $runDir = Join-Path (Get-CaseFolder 'Hay') ("{0}_{1}" -f $global:RunId, $(if ($Id) { $Id } else { $Command })); New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $b = Build-HayabusaArgs -Command $Command -InSpec $InSpec -Options $Options -OutDir $runDir
        $e.Command = $hi.Path; $e.Arguments = ConvertTo-ArgString $b.Args; $e.ToolVersion = $hi.Version
        foreach ($n in $b.Notes) { $e.Warnings += $n }
        if ($InSpec.Kind -in 'directory', 'file') { $e.Source = $InSpec.Path } elseif ($InSpec.Kind -eq 'live') { $e.Source = 'live event logs of this system' }
        # commands without a --rules option read ./rules from the working directory, so they start in the Hayabusa folder
        $wd = if ($b.NeedsToolDir) { $hi.Dir } else { $runDir }
        if ($b.NeedsToolDir) { $e.Warnings += 'This command always reads rules and writes its error log relative to the Hayabusa folder.' }
        $r = Invoke-As4Native -Exe $hi.Path -Arguments $b.Args -TimeoutSec 7200 -WorkDir $wd
        $e.ExitCode = $r.ExitCode; $e.StartUtc = $r.StartUtc
        $so = Join-Path $runDir 'raw_stdout.txt'; Write-As4File $so $r.StdOut; $files += $so
        $se = Join-Path $runDir 'raw_stderr.txt'; Write-As4File $se $r.StdErr; $files += $se
        $af = Join-Path $runDir 'arguments.json'
        Write-As4File $af ([ordered]@{ Executable = $hi.Path; Version = $hi.Version; Command = $Command; Arguments = $b.Args; CommandLine = $e.Arguments; Input = $InSpec; Options = $Options; Skipped = $b.Notes; StartUtc = $r.StartUtc; EndUtc = $r.EndUtc } | ConvertTo-Json -Depth 5); $files += $af
        $hf = Join-Path $runDir 'hayabusa_help_snapshot.txt'; Write-As4File $hf ((Get-HayabusaSpec $Command).Help); $files += $hf
        # scenario filter: keep only the rows that match, as a separate derived file (the full timeline stays untouched)
        if ($PostFilter -and $r.ExitCode -eq 0) {
            $tlf = @($b.Expected | Where-Object { $_ -like '*.csv' -and (Test-Path -LiteralPath $_) -and (Get-Item -LiteralPath $_).Length -lt 300MB })
            if ($tlf.Count) { try {
                $all = @(Import-Csv -LiteralPath $tlf[0]); $keep = @($all | Where-Object { ("$($_.RuleTitle) $($_.Details) $($_.ExtraFieldInfo)") -match $PostFilter }); $selfN = @($keep | Where-Object { Test-As4SelfText ("$($_.RuleTitle) $($_.Details) $($_.ExtraFieldInfo)") }).Count; if ($selfN) { $keep = @($keep | Where-Object { -not (Test-As4SelfText ("$($_.RuleTitle) $($_.Details) $($_.ExtraFieldInfo)")) }); $e.Notes += "$selfN detection(s) caused by AS4 itself were left out of findings_filtered.csv." }
                $ff = Join-Path $runDir 'findings_filtered.csv'; if ($keep.Count) { $keep | Export-Csv -LiteralPath $ff -NoTypeInformation -Encoding UTF8 } else { Write-As4File $ff '' }
                $e.Notes += "Scenario filter kept $($keep.Count) of $($all.Count) detections (findings_filtered.csv; timeline.csv has all of them)."
            } catch { $e.Warnings += "Scenario filter failed: $($_.Exception.Message)" } }
        }        foreach ($x in @(Get-ChildItem -LiteralPath $runDir -Recurse -File | Where-Object { $files -notcontains $_.FullName })) { $files += $x.FullName }
        $e.Status = Get-As4OpStatusFromResult $r
        $plain = Remove-AnsiCodes ($r.StdOut + "`n" + $r.StdErr)
        if ($e.Status -eq 'FAILED' -and $plain -match '(?i)(Total detection rules:\s*0\b|rules enabled after channel filter:\s*0\b|No rules were loaded)') { $e.Status = 'SKIPPED'; $e.Notes += 'No rule applies to these logs with these filters, so nothing was checked.' }
        if ($r.Error) { $e.Notes += $r.Error }
        if ($e.Status -eq 'OK') {
            $missing = @($b.Expected | Where-Object { -not (Test-Path -LiteralPath $_) })
            if ($missing.Count -and $Command -ne 'dfir-timeline') { $e.Notes += 'No result file was written (nothing matched).' }
            $tl = @($b.Expected | Where-Object { $_ -like '*.csv' -and (Test-Path -LiteralPath $_) -and (Get-Item -LiteralPath $_).Length -lt 300MB })
            if ($Command -eq 'dfir-timeline' -and $tl.Count) {
                try { $rows = @(Import-Csv -LiteralPath $tl[0]); $lv = $rows | Group-Object Level | ForEach-Object { "$($_.Name) $($_.Count)" }; $e.Notes += "$($rows.Count) detections ($($lv -join ', '))." } catch {}
            }
            if ($Command -eq 'dfir-timeline') { $e.Notes += 'Detections are rule matches (leads for review), not confirmed compromise.' }
        } else { $e.Notes += "exit=$($r.ExitCode)" }
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e $files 'derived'; Stop-As4Run; $res
}

function Import-HayabusaResults {
    param([string]$Path, [int]$Max = 5000)
    $out = @()
    $items = if (Test-Path -LiteralPath $Path -PathType Container) { Get-ChildItem -LiteralPath $Path -Recurse -File -Include *.csv, *.json, *.jsonl } else { @(Get-Item -LiteralPath $Path) }
    foreach ($f in $items) {
        if ($out.Count -ge $Max) { break }
        if ($f.Extension -eq '.json' -and ([IO.File]::ReadAllText($f.FullName).TrimStart().StartsWith('['))) { $out += @([IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json | Select-Object -First ($Max - $out.Count)) }
        elseif ($f.Extension -eq '.csv') { $out += @(Import-Csv -LiteralPath $f.FullName | Select-Object -First ($Max - $out.Count)) }
        elseif ($f.Extension -in '.jsonl', '.json') {
            $n = 0; foreach ($l in [IO.File]::ReadLines($f.FullName)) { if (-not $l.Trim() -or $n -ge $Max) { continue }; try { $out += ($l | ConvertFrom-Json); $n++ } catch {} }
        }
    }
    $out
}

# ================= SIMPLE MODE: ready-made investigation scenarios =================
$global:HayCoverage = $null
$global:HaySevRank = @{ critical = 5; high = 4; medium = 3; low = 2; info = 1 }

function Get-HayabusaScenarios {
    $f = Join-Path $global:P.Profiles 'scenarios_hayabusa.json'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    $o = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    foreach ($x in $o) { $x }
}

function Get-HayabusaRuleCoverage {
    # How many bundled rules look at each event ID (read once from the rule files).
    if ($global:HayCoverage) { return $global:HayCoverage }
    $idx = @{}; $hi = Get-HayabusaInfo
    if ($hi.Rules) {
        foreach ($y in Get-ChildItem -LiteralPath $hi.Rules -Recurse -Filter *.yml -ErrorAction SilentlyContinue) {
            $t = [IO.File]::ReadAllText($y.FullName)
            foreach ($m in [regex]::Matches($t, '(?m)^\s*(?:-\s*)?EventID:\s*(\d+)')) { $k = $m.Groups[1].Value; if ($idx.ContainsKey($k)) { $idx[$k]++ } else { $idx[$k] = 1 } }
        }
    }
    $global:HayCoverage = $idx; $idx
}

function Get-ScenarioRuleCount {
    param($Scenario)
    $ids = $Scenario.Options.'include-eid'; if (-not $ids) { return -1 }
    $cov = Get-HayabusaRuleCoverage; $n = 0
    foreach ($i in ("$ids" -split ',')) { if ($cov.ContainsKey($i.Trim())) { $n += $cov[$i.Trim()] } }
    $n
}

function Test-ScenarioLogs {
    # Returns the log types the scenario wants that are not in the chosen input (a hint, not an error).
    param($Scenario, [hashtable]$InSpec)
    if (-not $Scenario.Needs -or $InSpec.Kind -eq 'live' -or $InSpec.Kind -eq 'none') { return @() }
    $names = @(); if ($InSpec.Kind -eq 'file') { $names = @($InSpec.Path) } elseif (Test-Path -LiteralPath $InSpec.Path -PathType Container) { $names = @(Get-ChildItem -LiteralPath $InSpec.Path -Recurse -File -Filter *.evtx | ForEach-Object { $_.Name }) }
    $pat = @{ Security = '(^|[\\/])Security[_.]'; System = '(^|[\\/])System[_.]'; TerminalServices = 'TerminalServices|RdpCoreTS|RemoteDesktop'; WinRM = 'WinRM'; WMI = 'WMI-Activity'; PowerShell = 'PowerShell'; Sysmon = 'Sysmon'; TaskScheduler = 'TaskScheduler'; Defender = 'Defender' }
    $missing = @(); foreach ($n in $Scenario.Needs) { $rx = if ($pat.ContainsKey($n)) { $pat[$n] } else { $n }; if (-not (@($names | Where-Object { $_ -match $rx }).Count)) { $missing += $n } }
    $missing
}

function New-HayScenarioOptions {
    # Turns the three simple choices (when, how serious, report) into real Hayabusa options for this scenario.
    param($Scenario, [string]$Time = 'all', [string]$From, [string]$To, [string]$Severity = 'all', [bool]$Html = $true)
    $o = @{}; foreach ($pp in $Scenario.Options.PSObject.Properties) { $o[$pp.Name] = $pp.Value }
    $spec = Get-HayabusaSpec $Scenario.Command; $has = @{}; foreach ($s in $spec.Sections) { foreach ($x in $s.Options) { $has[$x.Long] = $true } }
    $notes = @()
    if ($has['--utc']) { $o['utc'] = $true }
    switch ($Time) {
        { $_ -in '24h', '7d', '30d' } { if ($has['--time-offset']) { $o['time-offset'] = $Time } else { $notes += 'This report ignores the time range.' } }
        'custom' {
            $fmt = 'yyyy-MM-dd'; $d1 = [datetime]::MinValue; $d2 = [datetime]::MinValue
            if ($From -and -not [datetime]::TryParseExact($From.Trim(), $fmt, $null, 'None', [ref]$d1)) { throw 'Dates must look like 2026-10-01.' }
            if ($To -and -not [datetime]::TryParseExact($To.Trim(), $fmt, $null, 'None', [ref]$d2)) { throw 'Dates must look like 2026-10-01.' }
            if ($has['--timeline-start']) { if ($From) { $o['timeline-start'] = $d1.ToString('yyyy-MM-dd') + ' 00:00:00 +00:00' }; if ($To) { $o['timeline-end'] = $d2.ToString('yyyy-MM-dd') + ' 23:59:59 +00:00' } } else { $notes += 'This report ignores custom dates.' } }
    }
    if ($Severity -in 'medium', 'high' -and $has['--min-level']) { $cur = $o['min-level']; $order = 'informational', 'low', 'medium', 'high', 'critical'; if (-not $cur -or [array]::IndexOf($order, $Severity) -gt [array]::IndexOf($order, "$cur")) { $o['min-level'] = $Severity } }
    if ($Html -and $has['--html-report']) { $o['html-report'] = $true }
    [pscustomobject]@{ Options = $o; Notes = $notes }
}

function Invoke-HayabusaScenario {
    param($Scenario, [hashtable]$InSpec, [string]$Time = 'all', [string]$From, [string]$To, [string]$Severity = 'all', [bool]$Html = $true)
    $so = New-HayScenarioOptions -Scenario $Scenario -Time $Time -From $From -To $To -Severity $Severity -Html $Html
    $r = Invoke-Hayabusa -Command $Scenario.Command -InSpec $InSpec -Options $so.Options -PostFilter $Scenario.Filter -Id $Scenario.Id -Title $Scenario.Title
    $r | Add-Member -NotePropertyName ScenarioNotes -NotePropertyValue $so.Notes -Force -PassThru
}

function ConvertTo-HaySeverity { param([string]$l) switch -Regex ($l) { '^crit' { 'critical' } '^high' { 'high' } '^med' { 'medium' } '^low' { 'low' } default { 'info' } } }

function Get-HayabusaFindings {
    # Reads the result of a scenario run into plain rows: Time, Severity, What happened, Computer, Where, Details.
    param($Result, [int]$Max = 5000)
    $file = @($Result.Destination | Where-Object { $_ -like '*findings_filtered.csv' } | Select-Object -First 1)
    if (-not $file.Count) { $file = @($Result.Destination | Where-Object { $_ -like '*timeline.csv' } | Select-Object -First 1) }
    $rows = @(); $csv = @()
    if ($file.Count) { $path = Join-Path $global:Case.Dir $file[0]; if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 0 -and (Get-Item -LiteralPath $path).Length -lt 400MB) { $csv = @(Import-Csv -LiteralPath $path) } }
    $csv = @($csv | Where-Object { -not (Test-As4SelfText ("$($_.RuleTitle) $($_.Details) $($_.ExtraFieldInfo)")) })   # AS4's own activity is not a finding about the machine
    foreach ($x in $csv) { $sev = ConvertTo-HaySeverity $x.Level
        $rows += [pscustomobject]@{ Time = $x.Timestamp; Severity = $sev; What = $x.RuleTitle; Computer = $x.Computer; Where = ("{0} / {1}" -f $x.Channel, $x.EventID); Details = $x.Details; Rank = $global:HaySevRank[$sev] } }
    $rows = @($rows | Sort-Object @{ e = 'Rank'; Descending = $true }, Time | Select-Object -First $Max)
    $by = @($csv | Group-Object { ConvertTo-HaySeverity $_.Level } | Sort-Object { $global:HaySevRank[$_.Name] } -Descending | ForEach-Object { "$($_.Name) $($_.Count)" })
    $top = @($csv | Group-Object RuleTitle | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Count))" })
    [pscustomobject]@{ Rows = $rows; Total = $csv.Count; BySeverity = $by; TopRules = $top }
}