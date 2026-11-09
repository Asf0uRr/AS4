# AS4 IR Tool - First Response: pick the situation, AS4 picks the collection. ASCII only.
# Order follows the order of volatility: snapshot, live state, hunt, files, event logs, report. Read-only.

function Get-As4Scenarios {
    $f = Join-Path $global:P.Profiles 'scenarios_collect.json'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    @($j | ForEach-Object { $_ })
}

function Get-As4ScenarioPlan {
    param($Scenario)
    $quick = @(Get-As4QuickTasks); $tri = @(Get-As4TriageTasks); $cat = @(Get-As4ArtifactCatalog); $ch = @(Get-As4EvtxChannels)
    $tasks = New-Object Collections.ArrayList; $missing = New-Object Collections.ArrayList
    foreach ($id in @($Scenario.Tasks)) {
        if ($id -eq '*quick') { foreach ($t in $quick) { if (-not ($tasks | Where-Object Id -eq $t.Id)) { [void]$tasks.Add($t) } } }
        elseif ($id -eq '*triage') { foreach ($t in $tri) { if (-not ($tasks | Where-Object Id -eq $t.Id)) { [void]$tasks.Add($t) } } }
        else { $t = @($quick + $tri) | Where-Object Id -eq $id | Select-Object -First 1; if ($t) { if (-not ($tasks | Where-Object Id -eq $t.Id)) { [void]$tasks.Add($t) } } else { [void]$missing.Add($id) } }
    }
    $arts = New-Object Collections.ArrayList
    foreach ($id in @($Scenario.Artifacts)) {
        if ($id -eq '*all-but-heavy') { foreach ($a in $cat) { if ($a.Id -notin 'ntfs', 'weblogs') { [void]$arts.Add($a) } } }
        else { $a = $cat | Where-Object Id -eq $id | Select-Object -First 1; if ($a) { [void]$arts.Add($a) } else { [void]$missing.Add($id) } }
    }
    $chn = New-Object Collections.ArrayList
    foreach ($g in @($Scenario.EventGroups)) { foreach ($c in $ch) { if (($g -eq '*all' -or $c.Group -eq $g) -and $chn -notcontains $c.Name) { [void]$chn.Add($c.Name) } } }
    $admin = @($tasks | Where-Object { $_.Admin -eq 'required' }).Count + @($arts | Where-Object { $_.Admin -eq 'required' }).Count + $(if ($chn -contains 'Security') { 1 } else { 0 })
    [pscustomobject]@{ Tasks = @($tasks); Artifacts = @($arts); Channels = @($chn); Missing = @($missing)
        AdminItems = $admin; Sensitive = @($arts | Where-Object { $_.Sensitive } | ForEach-Object { $_.Name }) + @($tasks | Where-Object { $_.Sensitive } | ForEach-Object { $_.Name })
        Steps = $tasks.Count + $arts.Count + $(if ($chn.Count) { 1 } else { 0 }) + $(if ($Scenario.Snapshot) { 1 } else { 0 }) + $(if ($Scenario.Hunt) { 1 } else { 0 }) + $(if ($Scenario.Autoruns) { 1 } else { 0 }) + 1 }
}

function Invoke-As4Scenario {
    param([Parameter(Mandatory)][string]$Id, [switch]$SkipSensitive, [scriptblock]$OnProgress)
    if (-not $global:Case) { throw 'No active case.' }
    $sc = Get-As4Scenarios | Where-Object Id -eq $Id | Select-Object -First 1
    if (-not $sc) { throw "Unknown scenario '$Id'." }
    $plan = Get-As4ScenarioPlan $sc
    $tasks = $plan.Tasks; $arts = $plan.Artifacts
    if ($SkipSensitive) { $tasks = @($tasks | Where-Object { -not $_.Sensitive }); $arts = @($arts | Where-Object { -not $_.Sensitive }) }
    $total = $plan.Steps; $global:ScN = 0; $scCb = $OnProgress   # not $OnProgress itself: called blocks can see a callee's own parameter of that name
    $say = { param($m) $global:ScN++; if ($scCb) { & $scCb ([Math]::Min($global:ScN, $total)) $total $m }; if ($global:UiPump) { & $global:UiPump } }
    Write-As4Log INFO "First Response '$($sc.Title)' started: $($tasks.Count) tasks, $($arts.Count) artifact groups, $($plan.Channels.Count) event logs"
    $results = New-Object Collections.ArrayList; $hunt = $null
    if ($sc.Snapshot -and -not $global:Cancel) { & $say 'Saving a snapshot of the machine state'; $sn = New-As4Snapshot; [void]$results.Add([pscustomobject]@{ Name = 'Snapshot'; Status = $sn.Status; Notes = $sn.Notes }) }
    if ($tasks.Count -and -not $global:Cancel) {
        $r = Invoke-As4Batch -Tasks $tasks -Label "scenario-$Id" -OnProgress { param($i, $n, $t) & $say "Collecting: $($t.Name)" }
        foreach ($x in @($r)) { [void]$results.Add($x) } }
    if ($sc.Hunt -and -not $global:Cancel) { & $say 'Running the Live Hunt'; $hunt = Invoke-LiveHunt -SkipFiles:$false -OnProgress { param($i, $n, $m) if ($scCb) { & $scCb ([Math]::Min($global:ScN, $total)) $total "Live Hunt: $m" } }; [void]$results.Add([pscustomobject]@{ Name = 'Live Hunt'; Status = $hunt.Status; Notes = $hunt.Notes }) }
    if ($arts.Count -and -not $global:Cancel) {
        $r = Invoke-As4Artifacts -Ids @($arts | ForEach-Object { $_.Id }) -Duplicates -OnProgress { param($i, $n, $c) & $say "Copying: $($c.Name)" }
        foreach ($x in @($r)) { [void]$results.Add($x) } }
    if ($plan.Channels.Count -and -not $global:Cancel) { & $say "Exporting $($plan.Channels.Count) event logs"; [void](Export-As4Evtx -Channels $plan.Channels) }
    if ($sc.Autoruns -and -not $global:Cancel) { & $say 'Autoruns'; if ((Get-As4Tool 'autorunsc').Path) { foreach ($x in @(Invoke-Autoruns)) { [void]$results.Add($x) } } }
    & $say 'Writing the case report'
    $rep = $null; try { $rep = New-As4Report $global:Case.Id } catch { Write-As4Log WARN "Report failed: $($_.Exception.Message)" }
    Write-As4Log OK "First Response '$($sc.Title)' finished"
    [pscustomobject]@{ Id = $Id; Title = $sc.Title; Results = @($results); Hunt = $hunt; Report = $rep; Plan = $plan }
}
