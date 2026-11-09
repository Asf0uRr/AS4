# AS4 IR Tool - CLI menus for First Response and Live Hunt. ASCII only.

function Write-CliVerdict {
    param($V, $Findings, $Next)
    $c = switch ($V.Color) { 'green' { 'Green' } 'yellow' { 'Yellow' } 'orange' { 'DarkYellow' } default { 'Red' } }
    Write-Host "`n  VERDICT: $($V.Verdict)   (score $($V.Score))" -ForegroundColor $c; Write-Host "  $($V.Text)"
    $cnt = @{ high = 0; medium = 0; low = 0; info = 0 }; foreach ($x in $Findings) { $cnt[$x.Sev]++ }
    Write-Host "  Leads: high $($cnt.high), medium $($cnt.medium), low $($cnt.low), info $($cnt.info)" -ForegroundColor White
    foreach ($x in ($Findings | Where-Object { $_.Sev -in 'high', 'medium' } | Select-Object -First 15)) { $k = 'Yellow'; if ($x.Sev -eq 'high') { $k = 'Red' }; Write-Host ("   [{0}] {1}" -f $x.Sev.ToUpper(), $x.Title) -ForegroundColor $k; Write-Host ('        ' + $x.Detail.Substring(0, [Math]::Min(150, $x.Detail.Length))) -ForegroundColor DarkGray }
    if ($Next) { Write-Host "`n  Next steps:"; $i = 0; foreach ($n in $Next) { $i++; Write-Host "   $i. $n" } }
}

function Menu-FirstResponse {
    if (-not (Require-Case)) { return }
    $sc = @(Get-As4Scenarios)
    Show-Banner; Write-Host '== First Response == what are you dealing with?' -ForegroundColor Cyan
    Write-Host '  AS4 collects in the order the data disappears, saves it in the case and writes a report. Read-only.' -ForegroundColor Gray; Write-Host ''
    $i = 0; foreach ($s in $sc) { $i++; $pl = Get-As4ScenarioPlan $s; Write-Host ('{0,3}. {1}' -f $i, $s.Title) -NoNewline; Write-Host ("  - $($s.Tagline)  ($($pl.Tasks.Count) checks, $($pl.Artifacts.Count) file groups, $($pl.Channels.Count) logs; about $($s.Minutes) min)") -ForegroundColor DarkGray }
    Write-Host "`n  ?N = what it does   number = run it   B = back"
    $in = Read-Host 'Select'; if ($in -match '^(b|back)$') { return }
    if ($in -match '^\?(\d+)$') { $n = [int]$Matches[1]; if ($n -ge 1 -and $n -le $sc.Count) { Write-Host "`n$($sc[$n - 1].When)" -ForegroundColor White }; Read-Host 'Enter' | Out-Null; return }
    if ($in -notmatch '^\d+$' -or [int]$in -lt 1 -or [int]$in -gt $sc.Count) { return }
    $s = $sc[[int]$in - 1]; $pl = Get-As4ScenarioPlan $s
    $m = "Run '$($s.Title)'? $($pl.Tasks.Count) checks, $($pl.Artifacts.Count) file groups, $($pl.Channels.Count) event logs."
    if ($pl.AdminItems -and -not (Test-As4Admin)) { $m += "`n$($pl.AdminItems) item(s) need administrator and will be skipped." }
    $skip = $false; if ($pl.Sensitive.Count) { Write-Host ('Private data is included: ' + (($pl.Sensitive | Select-Object -Unique) -join ', ')) -ForegroundColor Yellow; $skip = (Read-Host 'Skip those items? [Y/n]') -notmatch '^(n|no)$' }
    if (-not (Confirm-Action $m)) { return }
    $r = Invoke-As4Scenario -Id $s.Id -SkipSensitive:$skip -OnProgress { param($i, $n, $t) Write-Host "  [$i/$n] $t" -ForegroundColor Cyan }
    Show-ResultTable $r.Results
    if ($r.Hunt -and $r.Hunt.Verdict) { Write-CliVerdict $r.Hunt.Verdict $r.Hunt.Findings $r.Hunt.Next; Write-Host "`n  Hunt report: $($r.Hunt.Files.Html)" -ForegroundColor Green }
    if ($r.Report) { Write-Host "  Case report: $($r.Report.Html)" -ForegroundColor Green }
    Read-Host 'Enter' | Out-Null
}

function Menu-LiveHunt {
    if (-not (Require-Case)) { return }
    Show-Banner; Write-Host '== Live Hunt ==' -ForegroundColor Cyan
    Write-Host '  1. Live Hunt (about 30 s): does anything on this machine deserve attention?'; Write-Host '  2. Live Watch: record what starts and connects for a while'; Write-Host '  3. Take a snapshot of the machine state'; Write-Host '  4. Compare two snapshots (what changed?)'; Write-Host '  B. Back'
    try { switch (Read-Host 'Select') {
        '1' { $skipF = (Read-Host '  Skip the file scan to go faster? [y/N]') -match '^(y|yes)$'; $days = [int](Read-Line 'Event log days (3, 7, 14, 30)' '14')
            $r = Invoke-LiveHunt -EventDays $days -SkipFiles:$skipF -OnProgress { param($i, $n, $m) Write-Host "  [$i/$n] $m" -ForegroundColor Cyan }
            if ($r.Verdict) { Write-CliVerdict $r.Verdict $r.Findings $r.Next; Write-Host "`n  What this check could not see:" -ForegroundColor Yellow; $r.Blind | ForEach-Object { Write-Host "   - $_" -ForegroundColor DarkGray }; Write-Host "`n  Report: $($r.Files.Html)" -ForegroundColor Green } else { Write-Host "  Did not complete: $($r.Notes -join ' ')" -ForegroundColor Red } }
        '2' { $sec = [int](Read-Line 'Seconds to watch (10-3600)' '120'); $r = Invoke-LiveWatch -Seconds $sec -OnProgress { param($i, $n, $m) Write-Host "`r  $i/$n s  $m   " -NoNewline -ForegroundColor Cyan }
            Write-Host ''; Write-Host "  $($r.Notes -join ' ')"; if ($r.Verdict) { Write-CliVerdict $r.Verdict $r.Findings $null; Write-Host "`n  Report: $($r.Files.Html)" -ForegroundColor Green } }
        '3' { $r = New-As4Snapshot -Label (Read-Line 'Label (optional)' '') -OnProgress { param($i, $n, $m) Write-Host "  [$i/$n] $m" -ForegroundColor Cyan }; Write-Host "  $($r.Notes -join ' ')" -ForegroundColor Green }
        '4' { $sn = @(Get-As4Snapshots)
            if ($sn.Count -lt 1) { Write-Host '  No snapshots in this case yet.' -ForegroundColor Yellow }
            else { $i = 0; $sn | ForEach-Object { $i++; Write-Host ('{0,3}. {1}  {2}  {3}' -f $i, $_.Name, $_.Taken, $_.Label) }
                $a = [int](Read-Line 'Before (number)' ([Math]::Max(1, $sn.Count - 1))); $b = [int](Read-Line 'After (number)' $sn.Count)
                $c = Invoke-As4SnapshotCompare -Before $sn[$a - 1].Path -After $sn[$b - 1].Path; Write-Host "  $($c.Notes -join ' ')" -ForegroundColor Green
                $c.Rows | Where-Object { $_.Lead } | Select-Object -First 15 | ForEach-Object { Write-Host ("   [{0}] {1}: {2}  <= {3}" -f $_.Change, $_.Category, $_.Item, $_.Lead) -ForegroundColor Yellow }; Write-Host "  Report: $($c.Html)" -ForegroundColor Green } } } }
    catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Read-Host 'Enter' | Out-Null
}

function Menu-Parse {
    if (-not (Require-Case)) { return }
    $ps = @(Get-As4Parsers)
    Show-Banner; Write-Host '== Parse collected files ==' -ForegroundColor Cyan
    Write-Host '  Turns collected artifacts into CSV (15_Parsed). Reads files inside this case only.' -ForegroundColor Gray
    $i = 0; foreach ($x in $ps) { $i++; $t = Get-As4Tool $x.Tool; $n = 0; try { $n = @(& $x.Find).Count } catch {}; $tag = 'nothing to parse yet'; if (-not $t.Path) { $tag = 'parser missing' } elseif ($n) { $tag = "$n found" }; Write-Host ('{0,3}. {1}   [{2}]' -f $i, $x.Name, $tag) }
    Write-Host '  A = all   number list e.g. 1,3   B = back'
    $in = Read-Host 'Select'; if ($in -match '^(b|back)$') { return }
    try { $sel = if ($in -match '^(a|all)$') { $ps } else { Convert-Selection $in $ps.Count | ForEach-Object { $ps[$_ - 1] } }
        $r = Invoke-As4Parsers -Ids @($sel | ForEach-Object { $_.Id }) -OnProgress { param($i, $n, $m) Write-Host "  [$i/$n] $m" -ForegroundColor Cyan }; Show-ResultTable $r } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
    Read-Host 'Enter' | Out-Null
}
