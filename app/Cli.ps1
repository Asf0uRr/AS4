# AS4 IR Tool - interactive CLI. ASCII only.

function Show-Banner {
    $h = Get-As4Host
    Clear-Host
    Write-Host ''
    Write-Host ("  AS4 IR Tool {0}" -f $global:AS4Version) -ForegroundColor Cyan
    Write-Host ('  {0} | {1} | {2}' -f $h.Computer, $h.OS, $h.Arch) -ForegroundColor Gray
    $adm = if ($h.Admin) { 'administrator' } else { 'standard user (admin-only items will be skipped)' }
    Write-Host ('  Privileges: {0} | Free space: {1} GB' -f $adm, $h.DriveFreeGB) -ForegroundColor Gray
    if ($global:Case) { Write-Host ("  Case: {0}  ->  {1}" -f $global:Case.Id, $global:Case.Dir) -ForegroundColor Green }
    Write-Host ''
}
function Read-Line { param([string]$Prompt, [string]$Default)
    $s = if ($Default) { "$Prompt [$Default]: " } else { "${Prompt}: " }
    $v = Read-Host $s; if ([string]::IsNullOrWhiteSpace($v)) { $Default } else { $v.Trim() } }

function Confirm-Action { param([string]$Msg, [switch]$High)
    Write-Host $Msg -ForegroundColor Yellow
    $a = Read-Host $(if ($High) { 'Type YES to proceed' } else { 'Proceed? [y/N]' })
    if ($High) { $a -ceq 'YES' } else { $a -match '^(y|yes)$' } }

function Convert-Selection {
    param([string]$Text, [int]$Max)
    $set = New-Object Collections.Generic.SortedSet[int]
    foreach ($tok in ($Text -split '[,\s]+' | Where-Object { $_ })) {
        if ($tok -match '^(\d+)-(\d+)$') { $a = [int]$Matches[1]; $b = [int]$Matches[2]; if ($a -lt 1 -or $b -gt $Max -or $a -gt $b) { throw "Range '$tok' is out of bounds (1-$Max)." }; $a..$b | ForEach-Object { [void]$set.Add($_) } }
        elseif ($tok -match '^\d+$') { $n = [int]$tok; if ($n -lt 1 -or $n -gt $Max) { throw "Number $n is out of range (1-$Max)." }; [void]$set.Add($n) }
        else { throw "Cannot understand '$tok'. Use numbers like 1,3,5-8." }
    }
    @($set)
}

function Require-Case { if (-not $global:Case) { Write-Host 'No case is open.' -ForegroundColor Yellow; Read-Host 'Enter to continue' | Out-Null; $false } else { $true } }

function Invoke-CliTaskPicker {
    param([string]$Title, [object[]]$Tasks, [string]$Explain)
    if (-not (Require-Case)) { return }
    while ($true) {
        Show-Banner; Write-Host "== $Title ==" -ForegroundColor Cyan; Write-Host $Explain -ForegroundColor Gray; Write-Host ''
        $i = 0; foreach ($t in $Tasks) { $i++
            $flag = switch ($t.Admin) { 'required' { '[ADMIN]' } 'partial' { '[admin*]' } default { '       ' } }
            $q = if ($t.Quick) { 'Q' } else { ' ' }
            Write-Host ('{0,3}. {1} {2} {3}' -f $i, $q, $flag, $t.Name) -NoNewline; Write-Host ("   - " + $t.Desc) -ForegroundColor DarkGray }
        Write-Host "`n  Q = quick set (marked Q)   A = all   number list e.g. 1,4,7-9   B = back   ?N = details of N" -ForegroundColor Gray
        $in = Read-Host 'Select'
        if ($in -match '^(b|back|m|menu)$') { return }
        if ($in -match '^\?(\d+)$') { $n = [int]$Matches[1]; if ($n -ge 1 -and $n -le $Tasks.Count) { $t = $Tasks[$n - 1]; Write-Host "`n$($t.Name)`n  What: $($t.Desc)`n  Why:  $($t.Why)`n  Admin: $($t.Admin)   Sensitive: $($t.Sensitive)" -ForegroundColor White }; Read-Host 'Enter' | Out-Null; continue }
        $sel = @()
        try {
            if ($in -match '^(q|quick)$') { $sel = @($Tasks | Where-Object Quick) }
            elseif ($in -match '^(a|all)$') { $sel = @($Tasks) }
            else { $sel = @(Convert-Selection $in $Tasks.Count | ForEach-Object { $Tasks[$_ - 1] }) }
        } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Read-Host 'Enter' | Out-Null; continue }
        if (-not $sel.Count) { continue }
        if (-not (Confirm-Action "About to run $($sel.Count) read-only collection task(s) into $($global:Case.Dir)")) { continue }
        $res = Invoke-As4Batch -Tasks $sel -OnProgress { param($i, $n, $t) Write-Host ("[{0}/{1}] {2}" -f $i, $n, $t.Name) -ForegroundColor Cyan }
        Show-ResultTable $res; Read-Host 'Enter to continue' | Out-Null
    }
}

function Show-ResultTable {
    param($Res)
    Write-Host ''
    foreach ($r in $Res) { $c = switch ($r.Status) { 'OK' { 'Green' } 'SKIPPED' { 'Yellow' } 'CANCELLED' { 'Yellow' } default { 'Red' } }
        Write-Host ('  {0,-10} {1}' -f $r.Status, $r.Name) -ForegroundColor $c
        foreach ($n in @($r.Notes) + @($r.Warnings)) { if ($n) { Write-Host "             $n" -ForegroundColor DarkGray } } }
    $s = @($Res | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join '  '
    Write-Host "`n  Summary: $s" -ForegroundColor White
}

function Select-CliCase {
    # Asks for a case name. A folder with that name is created in output\ (or resumed if it exists).
    while ($true) {
        Show-Banner
        $c = @(Get-As4Cases)
        if ($c.Count) { Write-Host '  Existing cases:'; $c | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" } }
        Write-Host '  Everything you collect is saved in a folder with the case name, inside output\.' -ForegroundColor Gray
        $n = Read-Host '  Case name (empty to exit)'
        if ([string]::IsNullOrWhiteSpace($n)) { return $false }
        try { $r = Start-As4Case $n; if ($r.Resumed) { Write-Host '  Existing case opened. New files are added; nothing is overwritten.' -ForegroundColor Yellow; Start-Sleep 1 }; return $true }
        catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red; Read-Host '  Enter' | Out-Null }
    }
}
function Menu-EventLogs {
    if (-not (Require-Case)) { return }
    $ch = @(Get-As4EvtxChannels)
    Show-Banner; Write-Host '== Windows Event Logs ==' -ForegroundColor Cyan
    Write-Host 'Unfiltered export = original EVTX (05_Event_Logs\raw_evtx). Filtered export = DERIVED subset (filtered_evtx). No logs are cleared or modified.' -ForegroundColor Gray
    $i = 0; foreach ($c in $ch) { $i++; $a = if ($c.Admin) { '[ADMIN]' } else { '       ' }; Write-Host ('{0,3}. {1} [{2}] {3}  - {4}' -f $i, $a, $c.Group, $c.Name, $c.Desc) }
    Write-Host "`n  A = all that exist   C = core (System, Application, Security, PowerShell)   B = back"
    $in = Read-Host 'Select'
    if ($in -match '^(b|back)$') { return }
    try {
        $sel = if ($in -match '^(a|all)$') { $ch } elseif ($in -match '^(c|core)$') { $ch | Where-Object { $_.Group -in 'Core', 'PowerShell' } } else { Convert-Selection $in $ch.Count | ForEach-Object { $ch[$_ - 1] } }
        $ids = Read-Line 'Event ID filter (comma list, empty = none)' ''
        $from = Read-Line 'Start time UTC (e.g. 2026-10-01T00:00:00, empty = none)' ''
        $to = Read-Line 'End time UTC (empty = none)' ''
        $q = New-As4EvtxQuery -StartUtc $(if ($from) { [datetime]::Parse($from, $null, 'AdjustToUniversal,AssumeUniversal') }) -EndUtc $(if ($to) { [datetime]::Parse($to, $null, 'AdjustToUniversal,AssumeUniversal') }) -EventIds $ids
        if ($q) { Write-Host "Filtered export (derived data) with query: $q" -ForegroundColor Yellow }
        if (-not (Confirm-Action "Export $(@($sel).Count) channel(s)?")) { return }
        $out = Export-As4Evtx -Channels @($sel | ForEach-Object { $_.Name }) -Query $q -OnProgress { param($i, $n, $c) Write-Host "[$i/$n] $c" -ForegroundColor Cyan }
        Write-Host "Exported $(@($out).Count) file(s). See manifest for per-channel status." -ForegroundColor Green
    } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Read-Host 'Enter' | Out-Null
}

function Menu-QuickScan {
    if (-not (Require-Case)) { return }
    $hi = Get-HayabusaInfo
    if (-not $hi.Runnable) { Write-Host "Hayabusa is not available: $($hi.BlockReason)" -ForegroundColor Red; Read-Host 'Enter' | Out-Null; return }
    Show-Banner; Write-Host 'Quick Scan (optional) - is anything here worth a closer look?' -ForegroundColor Cyan
    Write-Host '  Runs the bundled Hayabusa rules on event logs. Local only: nothing is downloaded or sent anywhere.' -ForegroundColor Gray
    $d = @(Find-As4LogDirs $global:Case.Dir); Write-Host ("  Logs in this case: " + $(if ($d.Count) { "$(($d | Measure-Object Files -Sum).Sum) files in $($d.Count) folder(s)" } else { 'none yet' }))
    Write-Host '  1 = everything in this case   2 = another folder   3 = one file   4 = this computer (live)   B = back'
    $w = Read-Host 'Select'; if ($w -match '^[bB]$') { return }
    $src = switch ($w) { '2' { @{ Kind = 'directory'; Path = (Read-Line 'Folder') } } '3' { @{ Kind = 'file'; Path = (Read-Line 'File') } } '4' { @{ Kind = 'live' } } default { @{ Kind = 'case' } } }
    $fast = (Read-Host '  Fast mode, medium and above only? [y/N]') -match '^(y|yes)$'
    $so = $false; if ((Get-ChainsawInfo).Runnable -and $src.Kind -ne 'live') { $so = (Read-Host '  Second opinion with Chainsaw? [y/N]') -match '^(y|yes)$' }
    try {
        $res = Invoke-QuickScan -Source $src -Fast:$fast -SecondOpinion:$so -OnProgress { param($i, $n, $m) Write-Host "  [$i/$n] $m" -ForegroundColor Cyan }
        $a = $res.Analysis
        if (-not $a) { Write-Host "  Scan did not complete: $(@($res.Notes) -join ' ')" -ForegroundColor Red }
        else {
            $c = switch ($a.Color) { 'green' { 'Green' } 'yellow' { 'Yellow' } 'orange' { 'DarkYellow' } default { 'Red' } }
            Write-Host "`n  VERDICT: $($a.Verdict)   (score $($a.Score))" -ForegroundColor $c; Write-Host "  $($a.VerdictText)"
            Write-Host ("  Findings: " + (($a.Counts.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', '))
            if ($a.Window) { Write-Host "  Incident window: $(Format-QsDate $a.Window.From)  to  $(Format-QsDate $a.Window.To)" -ForegroundColor Yellow }
            Write-Host "`n  Why:"; $a.Reasons | ForEach-Object { Write-Host "   +$($_.Points)  $($_.Text)" }
            Write-Host "`n  Attack chain:" ; $a.Chain | Where-Object All | ForEach-Object { Write-Host ("   {0,-22} {1,5}  ({2} serious)" -f $_.Name, $_.All, $_.Serious) }
            Write-Host "`n  Top findings:"; $a.Rules | Select-Object -First 10 | ForEach-Object { Write-Host ("   [{0}] {1}  x{2}" -f $_.Sev.ToUpper(), $_.Title, $_.Count) }
            if ($a.Second) { Write-Host "`n  Second opinion: $($a.Second.Summary)" }
            if ($a.Blind.Count) { Write-Host "`n  Blind spots:" -ForegroundColor Yellow; $a.Blind | ForEach-Object { Write-Host "   - $_" } }
            Write-Host "`n  Next steps:"; $i = 0; $a.Next | ForEach-Object { $i++; Write-Host "   $i. $_" }
            Write-Host "`n  Saved: $($a.HtmlPath)`n         $($a.TextPath)" -ForegroundColor DarkGray
            Write-Host '  Rule matches are leads, not proof. No match is not proof of a clean machine.' -ForegroundColor DarkGray }
    } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Read-Host 'Enter' | Out-Null
}
function Get-HayFlatOptions {
    param([string]$Command)
    $spec = Get-HayabusaSpec $Command; $flat = @()
    foreach ($s in $spec.Sections) { foreach ($o in $s.Options) { if ($global:HayHidden -notcontains $o.Long -or $o.Long -eq '--html-report') { $flat += [pscustomobject]@{ Section = $s.Name; Opt = $o } } } }
    $flat
}

function Menu-Hayabusa {
    if (-not (Require-Case)) { return }
    $hi = Get-HayabusaInfo
    if (-not $hi.Runnable) { Write-Host "Hayabusa is not available: $($hi.BlockReason)" -ForegroundColor Red; Read-Host 'Enter' | Out-Null; return }
    $scen = @(Get-HayabusaScenarios)
    while ($true) {
        Show-Banner; Write-Host "Hayabusa  $($hi.Version)  -  what do you want to find?" -ForegroundColor Cyan
        $i = 0; $grp = ''
        foreach ($s in $scen) { $i++; if ($s.Group -ne $grp) { $grp = $s.Group; Write-Host "`n  $($grp.ToUpper())" -ForegroundColor DarkCyan }
            Write-Host ('  {0,2}. {1}' -f $i, $s.Title) -NoNewline; Write-Host ("   " + $s.Description) -ForegroundColor DarkGray }
        Write-Host "`n  Type numbers (1,3,5-7), A = all, V = advanced options, B = back"
        $k = Read-Host 'Select'
        if ($k -match '^[bB]$') { return }
        if ($k -match '^[vV]$') { Menu-HayabusaAdvanced; continue }
        try {
            $sel = if ($k -match '^[aA]$') { $scen } else { @(Convert-Selection $k $scen.Count | ForEach-Object { $scen[$_ - 1] }) }
            if (-not $sel.Count) { continue }
            Write-Host "`n  Which logs?   1 = exported in this case   2 = another folder   3 = one file   4 = this computer (live)"
            $w = Read-Host '  Logs [1]'; $in = switch ($w) { '2' { @{ Kind = 'directory'; Path = (Read-Line 'Folder') } } '3' { @{ Kind = 'file'; Path = (Read-Line 'File') } } '4' { @{ Kind = 'live'; Path = '' } } default { @{ Kind = 'directory'; Path = (Join-Path $global:Case.Dir '05_Event_Logs\raw_evtx') } } }
            if ($in.Kind -ne 'live' -and -not (Test-Path -LiteralPath $in.Path)) { Write-Host "  Not found: $($in.Path). Export event logs first (main menu 2)." -ForegroundColor Yellow; Read-Host 'Enter' | Out-Null; continue }
            $tw = Read-Host '  When?  1 = all time   2 = last 24 hours   3 = last 7 days   4 = last 30 days   5 = custom dates  [1]'
            $time = switch ($tw) { '2' { '24h' } '3' { '7d' } '4' { '30d' } '5' { 'custom' } default { 'all' } }; $from = ''; $to = ''
            if ($time -eq 'custom') { $from = Read-Line 'From (2026-10-01, empty = no limit)' ''; $to = Read-Line 'To (empty = no limit)' '' }
            $sv = Read-Host '  How serious?  1 = everything   2 = medium and above   3 = high and critical only  [1]'
            $sev = switch ($sv) { '2' { 'medium' } '3' { 'high' } default { 'all' } }
            $miss = @($sel | Where-Object { @(Test-ScenarioLogs $_ $in).Count }); if ($miss.Count) { Write-Host ("  Note: these need logs that are not in the input and will probably find nothing: " + (($miss | ForEach-Object { $_.Title }) -join '; ')) -ForegroundColor Yellow }
            if (-not (Confirm-Action "Run $($sel.Count) question(s)? Output goes to 11_Hayabusa_Analysis in the case folder.")) { continue }
            $all = @(); $n = 0
            foreach ($s in $sel) { $n++; Write-Host "[$n/$($sel.Count)] $($s.Title)" -ForegroundColor Cyan
                $res = Invoke-HayabusaScenario -Scenario $s -InSpec $in -Time $time -From $from -To $to -Severity $sev -Html $true; $f = Get-HayabusaFindings $res
                Write-Host ("      {0}  {1}" -f $res.Status, $(if ($s.Command -eq 'dfir-timeline') { "$($f.Total) findings $(($f.BySeverity) -join ', ')" } else { 'report saved' })) -ForegroundColor $(if ($res.Status -eq 'OK') { 'Green' } else { 'Yellow' })
                foreach ($x in ($f.Rows | Select-Object -First 8)) { $all += [pscustomobject]@{ Scenario = $s.Title; Time = $x.Time; Severity = $x.Severity; What = $x.What; Details = $x.Details } } }
            if ($all.Count) { Write-Host "`n  Top findings (full results are in the case folder):" -ForegroundColor White; $all | Sort-Object @{ e = { $global:HaySevRank[$_.Severity] }; Descending = $true } | Select-Object -First 25 | Format-Table Time, Severity, What, @{ n = 'Details'; e = { if ($_.Details.Length -gt 70) { $_.Details.Substring(0, 70) + '...' } else { $_.Details } } } -AutoSize | Out-Host }
            Write-Host '  Findings are rule matches for review, not proof of compromise.' -ForegroundColor DarkGray
        } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
        Read-Host 'Enter' | Out-Null
    }
}
function Menu-HayabusaAdvanced {
    if (-not (Require-Case)) { return }
    $hi = Get-HayabusaInfo
    if (-not $hi.Runnable) { Write-Host "Hayabusa is not available: $($hi.BlockReason)" -ForegroundColor Red; Read-Host 'Enter' | Out-Null; return }
    $presets = @(Get-HayabusaPresets); $cmds = @($global:HayCommands.Keys)
    $cmd = 'dfir-timeline'; $in = @{ Kind = 'directory'; Path = (Join-Path $global:Case.Dir '05_Event_Logs\raw_evtx') }; $opts = @{ utc = $true }
    while ($true) {
        Show-Banner; Write-Host "Hayabusa  $($hi.Version)  ($($hi.RuleFiles) rule files)" -ForegroundColor Cyan
        Write-Host "  Command : $cmd  -  $($global:HayCommands[$cmd])"
        Write-Host "  Input   : $($in.Kind) $($in.Path)"
        Write-Host ("  Options : " + $(if ($opts.Count) { (($opts.Keys | Sort-Object | ForEach-Object { if ($opts[$_] -eq $true) { "--$_" } else { "--$_ $($opts[$_])" } }) -join '  ') } else { '(none)' }))
        Write-Host ''
        Write-Host '  P. Apply a preset   C. Choose command   I. Set input   O. Set options (all of them)'
        Write-Host '  V. Show command line   H. Show help of this command   R. Run   B. Back'
        $k = Read-Host 'Select'
        try { switch -Regex ($k) {
            '^[pP]$' { $i = 0; $presets | ForEach-Object { $i++; Write-Host ("  {0,2}. {1}  -  {2}" -f $i, $_.Name, $_.Description) }
                       $n = (Convert-Selection (Read-Host 'Preset') $presets.Count)[0]; $pr = $presets[$n - 1]; $cmd = [string]$pr.Command; $opts = @{}
                       foreach ($pp in $pr.Options.PSObject.Properties) { if ($pp.Value) { $opts[$pp.Name] = $pp.Value } } }
            '^[cC]$' { $i = 0; $cmds | ForEach-Object { $i++; Write-Host ("  {0,2}. {1,-24} {2}" -f $i, $_, $global:HayCommands[$_]) }
                       $n = (Convert-Selection (Read-Host 'Command') $cmds.Count)[0]; $cmd = $cmds[$n - 1]; $opts = @{ utc = $true } }
            '^[iI]$' { $x = Read-Host '  1 = folder of .evtx   2 = one file   3 = live event logs of this system'
                       switch ($x) { '1' { $in = @{ Kind = 'directory'; Path = (Read-Line 'Folder' $in.Path) } } '2' { $in = @{ Kind = 'file'; Path = (Read-Line 'File') } } '3' { $in = @{ Kind = 'live'; Path = '' } } default { Write-Host '  Choose 1, 2 or 3.' -ForegroundColor Yellow } } }
            '^[oO]$' { $flat = @(Get-HayFlatOptions $cmd)
                       while ($true) {
                           $i = 0; $sec = ''; foreach ($f in $flat) { $i++; if ($f.Section -ne $sec) { $sec = $f.Section; Write-Host "`n  [$sec]" -ForegroundColor Cyan }
                               $o = $f.Opt; $key = $o.Long.Substring(2); $cur = if ($opts.ContainsKey($key)) { if ($opts[$key] -eq $true) { 'ON' } else { $opts[$key] } } else { '' }
                               $vn = if ($o.Value) { " <$($o.Value)$(if ($o.Multi) { '...' })>" } else { '' }
                               Write-Host ("  {0,3}. {1}{2}{3}" -f $i, $o.Long, $vn, $(if ($cur) { "   = $cur" } else { '' })) -NoNewline; Write-Host ("   " + $o.Desc) -ForegroundColor DarkGray }
                           $n = Read-Host "`n  Number to set or toggle (empty = done; 0 = clear all)"
                           if ([string]::IsNullOrWhiteSpace($n)) { break }
                           if ($n -eq '0') { $opts = @{}; continue }
                           $sel = (Convert-Selection $n $flat.Count)[0]; $o = $flat[$sel - 1].Opt; $key = $o.Long.Substring(2)
                           if (-not $o.Value) { if ($opts.ContainsKey($key)) { $opts.Remove($key) } else { $opts[$key] = $true } }
                           else { $hint = if ($global:HayEnums.ContainsKey($o.Long)) { " ($($global:HayEnums[$o.Long] -join '/'))" } elseif ($o.Long -eq '--profile') { " ($((Get-HayabusaProfiles) -join '/'))" } else { '' }
                                  $v = Read-Host "  $($o.Long) <$($o.Value)>$hint (empty = unset)"; if ([string]::IsNullOrWhiteSpace($v)) { [void]$opts.Remove($key) } else { $opts[$key] = $v.Trim() } }
                       } }
            '^[vV]$' { $b = Build-HayabusaArgs -Command $cmd -InSpec $in -Options $opts -OutDir '<case>\11_Hayabusa_Analysis\<run>'; Write-Host "`n$($hi.Path)`n$(ConvertTo-ArgString $b.Args)" -ForegroundColor White; $b.Notes | ForEach-Object { Write-Host "  note: $_" -ForegroundColor Yellow }; Read-Host 'Enter' | Out-Null }
            '^[hH]$' { Write-Host (Get-HayabusaSpec $cmd).Help; Read-Host 'Enter' | Out-Null }
            '^[rR]$' { if (Confirm-Action "Run Hayabusa $cmd now? Output goes to the case folder (11_Hayabusa_Analysis).") { Show-ResultTable @(Invoke-Hayabusa -Command $cmd -InSpec $in -Options $opts); Read-Host 'Enter' | Out-Null } }
            '^[bB]$' { return }
        } } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Read-Host 'Enter' | Out-Null }
    }
}
function Menu-Chainsaw {
    if (-not (Require-Case)) { return }
    while ($true) {
        Show-Banner; Write-Host '== Chainsaw ==' -ForegroundColor Cyan
        $ci = Get-ChainsawInfo
        if (-not $ci.Present) { Write-Host 'Chainsaw not found in tools\Chainsaw.' -ForegroundColor Red }
        else {
            Write-Host "Path: $($ci.Path)"
            if ($ci.Runnable) { Write-Host "Version: $($ci.Version)" -ForegroundColor Green } else { Write-Host "NOT RUNNABLE: $($ci.BlockReason)" -ForegroundColor Red }
        }
        Write-Host '  1. Show version / real help output   2. Hunt (Sigma/Chainsaw rules)   3. Search   4. Review results   B. Back'
        switch (Read-Host 'Select') {
            '1' { Get-ChainsawInfo -Refresh | Out-Null; $ci = Get-ChainsawInfo; if ($ci.Runnable) { $ci.Help.GetEnumerator() | ForEach-Object { Write-Host "--- $($_.Key) ---" -ForegroundColor Cyan; Write-Host $_.Value } } else { Write-Host 'Cannot run Chainsaw on this machine, so no help is available.' -ForegroundColor Yellow }; Read-Host 'Enter' | Out-Null }
            '2' { $profs = @(Get-ChainsawProfiles); $i = 0; $profs | ForEach-Object { $i++; Write-Host "  $i. $($_.Name) - $($_.Description)" }
                  try { $p = $profs[(Convert-Selection (Read-Host 'Profile') $profs.Count)[0] - 1]
                        $inp = Read-Line 'EVTX file or directory (e.g. a case raw_evtx folder)' (Join-Path $global:Case.Dir '05_Event_Logs\raw_evtx')
                        $fmt = Read-Line 'Output format (table/csv/json/log)' 'csv'
                        $O = @{ Input = @($inp); Format = $fmt; Sigma = (Resolve-ChainsawRel $ci.Dir $p.Sigma); Rules = (Resolve-ChainsawRel $ci.Dir $p.Rules); Mapping = (Resolve-ChainsawRel $ci.Dir $p.Mapping); Level = @($p.Level); SkipErrors = $true }
                        $r = Invoke-Chainsaw -Sub hunt -O $O; Show-ResultTable @($r) } catch { Write-Host $_.Exception.Message -ForegroundColor Red }; Read-Host 'Enter' | Out-Null }
            '3' { try { $O = @{ Input = @(Read-Line 'EVTX file or directory'); Pattern = (Read-Line 'Pattern/regex'); Format = (Read-Line 'Format (table/json)' 'json'); IgnoreCase = $true; SkipErrors = $true }
                        Show-ResultTable @(Invoke-Chainsaw -Sub search -O $O) } catch { Write-Host $_.Exception.Message -ForegroundColor Red }; Read-Host 'Enter' | Out-Null }
            '4' { try { $d = Read-Line 'Results file/folder'; Import-ChainsawResults $d | Select-Object -First 50 | Format-Table -AutoSize | Out-Host } catch { Write-Host $_.Exception.Message -ForegroundColor Red }; Read-Host 'Enter' | Out-Null }
            { $_ -match '^(b|back)$' } { return }
        }
    }
}

function Menu-Kape {
    if (-not (Require-Case)) { return }
    Show-Banner; Write-Host '== KAPE ==' -ForegroundColor Cyan
    Write-Host 'Targets collect artifacts from a source (live "C:" or a mounted image). Modules PROCESS already-collected data. Nothing is run unless you select it.' -ForegroundColor Gray
    $k = Get-KapeInfo
    if (-not $k.Present) { Write-Host 'KAPE is NOT present in tools\KAPE (licensed; obtain on the analyst workstation - see docs\TOOLS_INVENTORY.md).' -ForegroundColor Yellow; Read-Host 'Enter' | Out-Null; return }
    Write-Host "KAPE: $($k.Path) version=$($k.Version) targets=$($k.Targets.Count) modules=$($k.Modules.Count)" -ForegroundColor Green
    $profs = @(Get-KapeProfiles); $i = 0; $profs | ForEach-Object { $i++; Write-Host ("  {0}. {1} - {2} (targets: {3}; missing: {4})" -f $i, $_.Name, $_.Description, ($_.Targets -join ','), ($_.MissingTargets -join ',')) }
    Write-Host '  T. pick targets manually   B. back'
    $in = Read-Host 'Select'
    if ($in -match '^(b|back)$') { return }
    try {
        if ($in -match '^(t)$') { $j = 0; $k.Targets | ForEach-Object { $j++; Write-Host "  $j. $($_.Name) - $($_.Description)" }; $tg = @(Convert-Selection (Read-Host 'Targets (numbers)') $k.Targets.Count | ForEach-Object { $k.Targets[$_ - 1].Name }); $mod = @() }
        else { $p = $profs[(Convert-Selection $in $profs.Count)[0] - 1]; $tg = $p.Targets; $mod = $p.Modules }
        $src = Read-Line 'Source (live drive or mounted image path)' 'C:'
        if (Confirm-Action "KAPE will read from $src for targets: $($tg -join ', ') -> $($global:Case.Dir)\06_KAPE" -High) { Show-ResultTable @(Invoke-Kape -Source $src -Targets $tg -Modules $mod) }
    } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Read-Host 'Enter' | Out-Null
}

function Menu-Memory {
    Show-Banner; Write-Host 'Memory and disk imaging' -ForegroundColor Cyan
    Write-Host 'Capturing memory changes the running system and the image can contain credentials. It is saved only in the case folder (or the folder you choose).' -ForegroundColor Yellow
    Get-MemoryTools | Where-Object { $_ } | ForEach-Object { Write-Host ("  {0,-40} {1}" -f $_.Name, $_.Status) }
    Write-Host ''
    Write-Host '  1. Memory dump with FTK Imager (opens FTK Imager, then records the output)'
    Write-Host '  2. Memory dump with WinPmem'
    Write-Host '  3. Disk image with FTK Imager (graphical)'
    Write-Host '  4. Disk image with FTK Imager command line'
    Write-Host '  5. Record FTK Imager output already written (memory)   6. Record FTK output (disk)'
    Write-Host '  7. Analyse a dump with Volatility 3   8. Show tool help   B. Back'
    switch (Read-Host 'Select') {
        '1' { if (Confirm-Action 'Open FTK Imager? The case memory folder path will be copied to the clipboard.') { Show-ResultTable @(Start-FtkImager -Mode memory); Write-Host 'In FTK Imager: File > Capture Memory. Come back and choose 5 when it is done.' } }
        '2' { $t = Get-As4Tool 'winpmem'; if (-not $t.Path) { Write-Host 'WinPmem is not in tools\MemoryAcquisition.' -ForegroundColor Yellow; break }
              Write-Host (Get-MemToolHelp $t)
              $dest = Read-Line 'Destination folder' (Get-CaseFolder 'Mem'); $sp = Test-MemorySpace $dest
              Write-Host ("RAM {0} GB, free {1} GB at destination" -f [math]::Round($sp.RamBytes / 1GB, 1), [math]::Round($sp.FreeBytes / 1GB, 1))
              $tpl = Read-Line 'Arguments ({OUT} = output file; see help above)' '{OUT}'
              if (Confirm-Action "Run $($t.Path) $tpl ? This changes the running system and takes several minutes." -High) { Show-ResultTable @(Invoke-MemoryAcquisition -ToolId winpmem -DestDir $dest -ArgTemplate $tpl) } }
        '3' { if (Confirm-Action 'Open FTK Imager for a disk image?') { Show-ResultTable @(Start-FtkImager -Mode disk); Write-Host 'In FTK Imager: File > Create Disk Image. Come back and choose 6 when it is done.' } }
        '4' { if (Confirm-Action 'Run FTK Imager CLI?' ) { Show-ResultTable @(Invoke-FtkCliImage -Source (Read-Line 'Source (for example \\.\PHYSICALDRIVE1)') -Name (Read-Line 'Image name' 'disk_image') -Verify) } }
        '5' { Show-ResultTable @(Register-FtkOutput -Mode memory) }
        '6' { Show-ResultTable @(Register-FtkOutput -Mode disk) }
        '7' { Show-ResultTable @(Invoke-Volatility -Dump (Read-Line 'Memory dump path') -Plugin (Read-Line 'Plugin' 'windows.info')) }
        '8' { $id = Read-Line 'Tool id (winpmem/ftkimager/volatility3)' 'winpmem'; Write-Host (Get-MemToolHelp (Get-As4Tool $id)) }
    }
    Read-Host 'Enter' | Out-Null
}
function Menu-Artifacts {
    if (-not (Require-Case)) { return }
    $cat = @(Get-As4ArtifactCatalog)
    Show-Banner; Write-Host '== Disk & Artifacts ==' -ForegroundColor Cyan
    $i = 0; foreach ($c in $cat) { $i++; Write-Host ('{0,3}. [{1,-8}] {2}' -f $i, $c.Admin, $c.Name) -NoNewline; Write-Host ("  value:{0} sensitive:{1}" -f $c.Value, $c.Sensitive) -ForegroundColor DarkGray }
    Write-Host '  ?N = details   number list to collect   F = collect a custom folder   B = back'
    $in = Read-Host 'Select'
    if ($in -match '^(b|back)$') { return }
    try {
        if ($in -match '^\?(\d+)$') { $c = $cat[[int]$Matches[1] - 1]; Write-Host "`n$($c.Name)`n What: $($c.What)`n Why: $($c.Why)`n Value: $($c.Value)  Admin: $($c.Admin)  Sensitive: $($c.Sensitive)  Live collection: $($c.Live)`n $($c.Note)"; Read-Host 'Enter' | Out-Null; return }
        if ($in -match '^f$') {
            $f = @((Read-Line 'Folder(s), comma separated') -split ','); $days = Read-Line 'Only files changed in last N days (empty = all)' ''; $ext = Read-Line 'Extensions (e.g. exe,dll; empty = all)' ''; $mb = Read-Line 'Max file size MB (empty = no limit)' '0'
            if (Confirm-Action 'Copy matching files into the case (read-only on source)?') { Show-ResultTable @(Invoke-As4FolderCollection -Folders ($f | ForEach-Object { $_.Trim() }) -Since $(if ($days) { (Get-Date).AddDays(-[int]$days) }) -Extensions @($ext -split ',' | Where-Object { $_ }) -MaxMB ([double]$mb) -Duplicates) }
        } else {
            $sel = @(Convert-Selection $in $cat.Count | ForEach-Object { $cat[$_ - 1] })
            if (Confirm-Action "Collect $($sel.Count) categor(ies)? Sensitive data may be copied: $((($sel | Where-Object Sensitive).Name) -join '; ')") { Show-ResultTable (Invoke-As4Artifacts -Ids @($sel.Id) -Duplicates -OnProgress { param($i, $n, $c) Write-Host "[$i/$n] $($c.Name)" -ForegroundColor Cyan }) }
        }
    } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Read-Host 'Enter' | Out-Null
}

function Menu-Analysis {
    if (-not (Require-Case)) { return }
    Show-Banner; Write-Host '== Analysis (offline) ==' -ForegroundColor Cyan
    Write-Host '  1. IOC search in collected files   2. YARA scan   3. Prepare UTC timeline CSV   B. Back'
    try { switch (Read-Host 'Select') {
        '1' { $r = Invoke-As4IocSearch -IocFile (Read-Line 'IOC list file (one per line)') -SearchRoot (Read-Line 'Folder to search' $global:Case.Dir); $r | Format-List | Out-Host }
        '2' { Show-ResultTable @(Invoke-Yara -Rules (Read-Line 'YARA rule file') -Target (Read-Line 'File/folder to scan')) }
        '3' { Invoke-As4Timeline | Format-List | Out-Host } } } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Read-Host 'Enter' | Out-Null
}

function Menu-Integrity {
    if (-not (Require-Case)) { return }
    Show-Banner; Write-Host '== Integrity & Reports ==' -ForegroundColor Cyan
    Write-Host '  1. Verify case hashes   2. Generate HTML/CSV/JSON report   3. Show run summary   B. Back'
    try { switch (Read-Host 'Select') {
        '1' { $v = Invoke-As4Verify $global:Case.Id; Write-Host "Checked $($v.Total): OK=$($v.OK) problems=$($v.Problems)  report: $($v.Report)" -ForegroundColor $(if ($v.Problems) { 'Red' } else { 'Green' }); $v.Details | Format-Table | Out-Host }
        '2' { $r = New-As4Report $global:Case.Id; Write-Host "Report: $($r.Html)" -ForegroundColor Green }
        '3' { Get-As4Summary $global:Case.Dir | Format-List | Out-Host } } } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Read-Host 'Enter' | Out-Null
}

function Menu-Tools {
    Show-Banner; Write-Host '== Tool inventory ==' -ForegroundColor Cyan
    Get-As4Tools | Format-Table Name, Status, FileVersion, License -AutoSize | Out-Host
    Write-Host 'PRESENT_UNVERIFIED = file exists but its SHA-256 is not recorded in config\tools_manifest.json (register it with scripts\Prepare-Tools.ps1 on the analyst workstation).' -ForegroundColor Gray
    Read-Host 'Enter' | Out-Null
}

function Show-Help {
    Show-Banner
    Write-Host @'
HELP
  - The case name you entered creates (or reopens) a folder in output\. All output goes to output\<CASE>\ in numbered folders.
  - Quick Response (2) collects host state with native Windows commands (read-only).
  - Selections: type numbers (1,3,5-8), Q for the quick set, A for all, B to go back.
  - Items marked [ADMIN] are skipped when not elevated; [admin*] may be incomplete.
  - Nothing is ever deleted, killed, quarantined or remediated. Nothing is downloaded or installed.
  - Every action is written to output\<CASE>\13_Collection_Logs\manifest.jsonl with UTC times, exit codes, hashes.
  - Batch mode:  AS4_IR_Tool_CLI.exe -Batch quick -Case "Case name"
'@
    Read-Host 'Enter' | Out-Null
}

function Start-As4Cli {
    if (-not $global:Case) { if (-not (Select-CliCase)) { return } }
    while ($true) {
        Show-Banner
        Write-Host '   1. Quick Response            8. Hayabusa'; Write-Host '   2. Event Logs                9. Chainsaw'; Write-Host '   3. Artifacts                10. KAPE'
        Write-Host '   4. Persistence triage       11. IOC, YARA, Timeline'; Write-Host '   5. Memory                   12. Report and integrity'; Write-Host '   6. Disk image (FTK Imager)  13. Tools'; Write-Host '   7. Quick Scan (logs: is something wrong?)'
        Write-Host '  14. First Response (pick the situation)   15. Live Hunt / Watch / Snapshots'; Write-Host '   C. Change case    H. Help    Q. Quit'
        switch -Regex (Read-Host 'Select') {
            '^1$' { Invoke-CliTaskPicker 'Quick Response' (Get-As4QuickTasks) 'Built-in Windows commands and read-only queries. Pick items, or Q for the quick set.' }
            '^2$' { Menu-EventLogs } '^3$' { Menu-Artifacts }
            '^4$' { $t = @(Get-As4TriageTasks); Invoke-CliTaskPicker 'Persistence triage' $t 'Collection and heuristic leads only. Nothing is stopped, deleted or removed.'
                    if ((Get-As4Tool 'autorunsc').Path -and (Confirm-Action 'Also run Autoruns? WARNING: it writes an EULA value to the registry of this machine (the only item that does). Skip it on infected or evidence machines.')) { Show-ResultTable @(Invoke-Autoruns); Read-Host 'Enter' | Out-Null } }
            '^(5|6)$' { Menu-Memory } '^7$' { Menu-QuickScan } '^8$' { Menu-Hayabusa } '^9$' { Menu-Chainsaw } '^10$' { Menu-Kape } '^11$' { Menu-Analysis } '^12$' { Menu-Integrity } '^13$' { Menu-Tools } '^14$' { Menu-FirstResponse } '^15$' { Menu-LiveHunt }
            '^(c|case)$' { [void](Select-CliCase) }
            '^(h|help|\?)$' { Show-Help }
            '^(q|quit|exit)$' { return }
        }
    }
}