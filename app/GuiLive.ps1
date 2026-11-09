# AS4 IR Tool - pages for First Response and Live Hunt. ASCII only.

function Get-LhBannerColor { param($c) switch ($c) { 'green' { [Drawing.Color]::FromArgb(46, 125, 79) } 'yellow' { [Drawing.Color]::FromArgb(154, 123, 23) } 'orange' { [Drawing.Color]::FromArgb(180, 96, 26) } 'red' { [Drawing.Color]::FromArgb(169, 50, 50) } default { [Drawing.Color]::FromArgb(122, 31, 31) } } }

# draws a verdict, the findings and what to do next into a panel; returns the height used
function Show-LhResult {
    param($Out, $Title, $Verdict, $Findings, $Next, $Blind, $Files, $Events)
    $Out.Controls.Clear(); $y = 0
    $ban = New-Object Windows.Forms.Panel; $ban.Location = New-Object Drawing.Point(0, 0); $ban.Size = New-Object Drawing.Size(980, 78); $ban.BackColor = (Get-LhBannerColor $Verdict.Color); $ban.Anchor = 'Top,Left,Right'; $Out.Controls.Add($ban)
    $ban.Controls.Add((NLabel "${Title}:  $($Verdict.Verdict)   (score $($Verdict.Score))" 14 8 940 30 ([Drawing.Color]::White) (F 15 'Bold'))); $ban.Controls.Add((NLabel $Verdict.Text 16 42 950 32 ([Drawing.Color]::White) (F 9))); $y = 88
    $cnt = @{ high = 0; medium = 0; low = 0; info = 0 }; foreach ($x in $Findings) { $cnt[$x.Sev]++ }
    $Out.Controls.Add((NLabel "Leads:   high $($cnt.high)      medium $($cnt.medium)      low $($cnt.low)      info $($cnt.info)" 0 $y 980 20 $global:C.Text (F 9.5 'Bold'))); $y += 26
    if ($Verdict.Reasons.Count) { $Out.Controls.Add((NSection 'WHY THIS VERDICT' 0 $y 400)); $y += 20; $why = ($Verdict.Reasons | Select-Object -First 8 | ForEach-Object { "+$($_.Points)   $($_.Text)" }) -join "`r`n"; $h = 17 * [Math]::Min(8, $Verdict.Reasons.Count) + 4; $Out.Controls.Add((NLabel $why 0 $y 980 $h $global:C.Text (F 8.5))); $y += $h + 8 }
    $Out.Controls.Add((NSection 'FINDINGS  (select a row to read why it matters and what to do)' 0 $y 700)); $y += 22
    $g = NGrid 0 $y 980 210; $g.Anchor = 'Top,Left,Right'; $g.SelectionMode = 'FullRowSelect'; $g.MultiSelect = $false
    $dt = New-Object Data.DataTable; foreach ($c in 'Level', 'Area', 'What', 'Detail') { [void]$dt.Columns.Add($c) }
    foreach ($x in $Findings) { [void]$dt.Rows.Add($x.Sev, $x.Area, $x.Title, $x.Detail) }
    $g.DataSource = $dt
    $g.Add_CellFormatting({ param($s, $e) if ($e.RowIndex -ge 0) { $v = [string]$s.Rows[$e.RowIndex].Cells['Level'].Value; $c = switch ($v) { 'high' { [Drawing.Color]::FromArgb(112, 38, 38) } 'medium' { [Drawing.Color]::FromArgb(104, 92, 36) } 'low' { [Drawing.Color]::FromArgb(38, 66, 104) } default { $null } }; if ($c -and $e.ColumnIndex -eq 0) { $e.CellStyle.BackColor = $c; $e.CellStyle.ForeColor = [Drawing.Color]::White } } })
    $Out.Controls.Add($g); $y += 218
    $det = NLabel 'Select a finding above.' 0 $y 980 74 $global:C.Dim (F 9); $det.BackColor = $global:C.Panel; $Out.Controls.Add($det); $y += 82
    $fl = @($Findings)
    $g.Add_SelectionChanged({ if ($g.SelectedRows.Count -eq 1) { $i = $g.SelectedRows[0].Index; if ($i -ge 0 -and $i -lt $fl.Count) { $x = $fl[$i]; $t = "Why it matters: $($x.Why)`r`nWhat to do next: $($x.Next)"; if ($x.Mitre) { $t += "`r`nMITRE ATT&CK: $($x.Mitre)" }; $det.Text = $t; $det.ForeColor = $global:C.Text } } }.GetNewClosure())
    if ($Events -and @($Events).Count) {
        $Out.Controls.Add((NSection 'EVERYTHING THAT APPEARED WHILE WATCHING' 0 $y 600)); $y += 22
        $eg = NGrid 0 $y 980 180; $eg.Anchor = 'Top,Left,Right'; $edt = New-Object Data.DataTable; foreach ($c in 'Time (UTC)', 'What', 'Name', 'Detail') { [void]$edt.Columns.Add($c) }
        foreach ($ev in $Events) { [void]$edt.Rows.Add($ev.TimeUtc.Substring(11, 8), $ev.Type, $ev.Subject, $ev.Detail) }
        $eg.DataSource = $edt; $Out.Controls.Add($eg); $y += 190 }
    if ($Next -and @($Next).Count) { $Out.Controls.Add((NSection 'NEXT STEPS' 0 $y 400)); $y += 20; $i = 0; $nt = ($Next | ForEach-Object { $i++; "$i. $_" }) -join "`r`n"; $nh = 34 * @($Next).Count; $Out.Controls.Add((NLabel $nt 0 $y 980 $nh $global:C.Text (F 8.5))); $y += $nh + 6 }
    if ($Blind -and @($Blind).Count) { $Out.Controls.Add((NSection 'WHAT THIS CHECK COULD NOT SEE' 0 $y 600)); $y += 20; $bt = ($Blind | ForEach-Object { "- $_" }) -join "`r`n"; $bh = 32 * @($Blind).Count; $Out.Controls.Add((NLabel $bt 0 $y 980 $bh $global:C.Warn (F 8.5))); $y += $bh + 6 }
    $x0 = 0; $hp = $Files.Html; $tp = $Files.Text
    if ($hp) { $b1 = NButton 'Open report (HTML)' $x0 $y 170 32 $true; $b1.Add_Click({ Start-Process $hp }.GetNewClosure()); $Out.Controls.Add($b1); $x0 += 180 }
    if ($tp) { $b2 = NButton 'Open text version' $x0 $y 160 32; $b2.Add_Click({ Start-Process $tp }.GetNewClosure()); $Out.Controls.Add($b2); $x0 += 170 }
    $b3 = NButton 'Open results folder' $x0 $y 170 32; $b3.Add_Click({ Start-Process explorer.exe -ArgumentList (ConvertTo-ArgString @((Get-CaseFolder 'Live'))) }); $Out.Controls.Add($b3); $y += 44
    $Out.Controls.Add((NLabel 'Every item is a lead for a person to confirm, not proof. Nothing on this machine was changed.' 0 $y 980 18 $global:C.Dim (F 8))); $y += 24
    $Out.Height = $y
    $y
}

function Show-SnapshotCompareDialog {
    $snaps = @(Get-As4Snapshots); if ($snaps.Count -lt 1) { Gui-Msg 'Take at least one snapshot first. Take one now, do the thing you want to measure, then take another.' 'Compare'; return $null }
    $f = New-Object Windows.Forms.Form; $f.Text = 'Compare two snapshots'; $f.Size = New-Object Drawing.Size(640, 300); $f.StartPosition = 'CenterParent'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.BackColor = $global:C.Bg; $f.ForeColor = $global:C.Text; $f.Font = F 9
    $items = @($snaps | ForEach-Object { "$($_.Name)   $($_.Taken)   $($_.Label)" })
    $f.Controls.Add((NLabel 'Before (older)' 20 18 300 20 $global:C.Text (F 9 'Bold'))); $c1 = NCombo 20 40 580; [void]$c1.Items.AddRange($items); [void]$c1.Items.Add('Another file...'); $f.Controls.Add($c1)
    $f.Controls.Add((NLabel 'After (newer)' 20 84 300 20 $global:C.Text (F 9 'Bold'))); $c2 = NCombo 20 106 580; [void]$c2.Items.AddRange($items); [void]$c2.Items.Add('Another file...'); $f.Controls.Add($c2)
    if ($items.Count -ge 2) { $c1.SelectedIndex = $items.Count - 2; $c2.SelectedIndex = $items.Count - 1 } else { $c1.SelectedIndex = 0 }
    $f.Controls.Add((NLabel 'A snapshot taken on another computer or from a clean reference machine works too.' 20 148 580 20 $global:C.Dim))
    $ok = NButton 'Compare' 400 200 100 32 $true; $cn = NButton 'Cancel' 510 200 100 32; $f.Controls.AddRange(@($ok, $cn)); $f.AcceptButton = $ok; $f.CancelButton = $cn
    $state = @{ A = $null; B = $null; Ok = $false }
    $pick = { param($combo, $key) if ($combo.SelectedIndex -eq $items.Count) { $d = New-Object Windows.Forms.OpenFileDialog; $d.Filter = 'Snapshot|snapshot_*.json|JSON|*.json'; if ($d.ShowDialog() -eq 'OK') { $state[$key] = $d.FileName } else { $combo.SelectedIndex = 0 } } elseif ($combo.SelectedIndex -ge 0) { $state[$key] = $snaps[$combo.SelectedIndex].Path } }.GetNewClosure()
    $c1.Add_SelectedIndexChanged({ & $pick $c1 'A' }.GetNewClosure()); $c2.Add_SelectedIndexChanged({ & $pick $c2 'B' }.GetNewClosure())
    & $pick $c1 'A'; & $pick $c2 'B'
    $ok.Add_Click({ if ($state.A -and $state.B -and $state.A -ne $state.B) { $state.Ok = $true; $f.Close() } else { Gui-Msg 'Choose two different snapshots.' 'Compare' } }.GetNewClosure()); $cn.Add_Click({ $f.Close() }.GetNewClosure())
    [void]$f.ShowDialog($global:G.Form)
    if ($state.Ok) { return @($state.A, $state.B) }
    $null
}

function Build-LiveHunt {
    $p = NPanel; foreach ($c in (NHeading 'Live Hunt' 'Look at this running machine and get a plain answer: does anything here deserve attention? It reads processes, connections, services, autostarts, accounts, security settings, event logs and recent files, scores them, and changes nothing.')) { $p.Controls.Add($c) }
    $card = { param($x, $title, $w) $c = New-Object Windows.Forms.Panel; $c.Location = New-Object Drawing.Point($x, 84); $c.Size = New-Object Drawing.Size($w, 126); $c.BackColor = $global:C.Panel; $c.Controls.Add((NLabel $title 12 8 ($w - 24) 18 $global:C.Accent (F 9 'Bold'))); $p.Controls.Add($c); $c }
    $c1 = & $card 20 'LIVE HUNT  (about 30 seconds)' 360; $c2 = & $card 390 'LIVE WATCH  (see what starts or connects)' 330; $c3 = & $card 730 'SNAPSHOTS  (what changed?)' 270
    $bh = NButton 'Run Live Hunt' 12 34 170 36 $true 'Checks processes, network, services, persistence, accounts, defences, event logs and recently dropped files. Results go to 14_Live_Analysis.'; $c1.Controls.Add($bh)
    $skipF = NCheck 'Skip the file scan (faster)' 190 36 165; $c1.Controls.Add($skipF)
    $gentleCb = NCheck 'Gentle mode (servers)' 190 58 165 'Longer pauses, fewer signature checks, no file scan. Chosen automatically on servers and busy machines.'; $c1.Controls.Add($gentleCb)
    $c1.Controls.Add((NLabel 'Event log days' 12 82 90 20 $global:C.Dim)); $dd = NCombo 104 78 70; [void]$dd.Items.AddRange(@('3', '7', '14', '30')); $dd.SelectedIndex = 2; $c1.Controls.Add($dd)
    $c1.Controls.Add((NLabel 'Administrator shows more (Security log, all paths).' 190 82 165 36 $global:C.Dim (F 8)))
    $c2.Controls.Add((NLabel 'Watch for' 12 40 70 20 $global:C.Dim)); $dur = NCombo 84 36 110; [void]$dur.Items.AddRange(@('30 seconds', '1 minute', '2 minutes', '5 minutes', '10 minutes')); $dur.SelectedIndex = 2; $c2.Controls.Add($dur)
    $bw = NButton 'Start watching' 204 34 110 32 $true 'Checks every 3 seconds (5 on servers) and records new programs, internet connections, listeners and DNS lookups. Reconnects at a steady rhythm are flagged.'; $c2.Controls.Add($bw)
    $c2.Controls.Add((NLabel 'Use it while you reproduce the problem, or just let it run to catch beacons. Quick programs can be missed.' 12 78 306 40 $global:C.Dim (F 8)))
    $bs = NButton 'Take snapshot' 12 34 120 32 $false 'Saves the programs, services, tasks, autostarts, ports, accounts and software as they are now.'; $c3.Controls.Add($bs)
    $bc = NButton 'Compare...' 142 34 110 32 $false 'Shows what was added, removed or changed between two snapshots.'; $c3.Controls.Add($bc)
    $c3.Controls.Add((NLabel 'Snapshot, do the thing, snapshot again, compare.' 12 78 250 40 $global:C.Dim (F 8)))
    $out = New-Object Windows.Forms.Panel; $out.Location = New-Object Drawing.Point(20, 224); $out.Size = New-Object Drawing.Size(1000, 40); $out.BackColor = $global:C.Bg; $out.Anchor = 'Top,Left,Right'; $p.Controls.Add($out)
    $global:G.LiveOut = $out
    $bh.Add_Click({ if (-not (Gui-Confirm "Run the Live Hunt on this computer?`r`nIt only reads. It takes about half a minute and runs at low priority.")) { return }
        if ($gentleCb.Checked) { $global:LhGentle = $true } else { $global:LhGentle = $null }
        Gui-Run { $r = Invoke-LiveHunt -EventDays ([int]$dd.SelectedItem) -SkipFiles:$skipF.Checked -OnProgress { param($i, $n, $m) Gui-Progress $i $n $m }; Gui-ShowResults @($r.Entry)
            if ($r.Verdict) { [void](Show-LhResult $out 'Live Hunt' $r.Verdict $r.Findings $r.Next $r.Blind $r.Files $null) } } 'Live Hunt' }.GetNewClosure())
    $bw.Add_Click({ $sec = @(30, 60, 120, 300, 600)[$dur.SelectedIndex]
        if (-not (Gui-Confirm "Watch this computer for $sec seconds?`r`nIt checks every 3 seconds (5 on servers). You can press Cancel to stop early and keep what was seen.")) { return }
        Gui-Run { $r = Invoke-LiveWatch -Seconds $sec -OnProgress { param($i, $n, $m) Gui-Progress $i $n "watching: $m" }; Gui-Log INFO ($r.Notes -join ' ')
            if ($r.Verdict) { [void](Show-LhResult $out 'Live Watch' $r.Verdict $r.Findings @() @() $r.Files $r.Events) } } 'Live Watch' }.GetNewClosure())
    $bs.Add_Click({ Gui-Run { $r = Invoke-Snapshot-Gui; } 'Snapshot' }.GetNewClosure())
    $bc.Add_Click({ $pair = Show-SnapshotCompareDialog; if (-not $pair) { return }
        Gui-Run { $c = Invoke-As4SnapshotCompare -Before $pair[0] -After $pair[1]; Gui-Log OK ($c.Notes -join ' '); if ($c.Html) { Start-Process $c.Html } } 'Comparing snapshots' }.GetNewClosure())
    $p
}
function Invoke-Snapshot-Gui {
    $r = New-As4Snapshot -Label ((Get-Date).ToString('HH:mm')) -OnProgress { param($i, $n, $m) Gui-Progress $i $n $m }
    if ($r.Status -eq 'OK') { Gui-Log OK ($r.Notes -join ' ') } else { Gui-Log ERROR ($r.Notes -join ' ') }
    $r
}

function Build-FirstResponsePage {
    $p = NPanel; foreach ($c in (NHeading 'First Response' 'Tell AS4 what you are dealing with. It picks what to collect, in the order the data disappears, saves it in the case and finishes with a report. Everything is read-only and local.')) { $p.Controls.Add($c) }
    $skip = NCheck 'Skip items that hold private data (browser history, user activity, PowerShell history)' 20 82 700 'Leave this ticked unless you have authority to collect personal data.'; $p.Controls.Add($skip)
    $list = New-Object Windows.Forms.Panel; $list.Location = New-Object Drawing.Point(20, 112); $list.Size = New-Object Drawing.Size(1000, 540); $list.AutoScroll = $true; $list.Anchor = 'Top,Left,Right,Bottom'; $list.BackColor = $global:C.Bg; $p.Controls.Add($list)
    $y = 0
    foreach ($sc in (Get-As4Scenarios)) {
        $plan = Get-As4ScenarioPlan $sc
        $card = New-Object Windows.Forms.Panel; $card.Location = New-Object Drawing.Point(0, $y); $card.Size = New-Object Drawing.Size(960, 118); $card.BackColor = $global:C.Panel; $card.Anchor = 'Top,Left,Right'; $list.Controls.Add($card)
        $card.Controls.Add((NLabel $sc.Title 14 8 560 24 $global:C.Text (F 12 'Bold'))); $card.Controls.Add((NLabel $sc.Tagline 14 34 600 18 $global:C.Accent (F 9)))
        $card.Controls.Add((NLabel $sc.When 14 56 700 56 $global:C.Dim (F 8.5)))
        $adm = if ($plan.AdminItems) { "$($plan.AdminItems) item(s) need administrator" } else { 'no administrator needed' }
        $card.Controls.Add((NLabel "$($plan.Tasks.Count) checks, $($plan.Artifacts.Count) file groups, $($plan.Channels.Count) event logs`r`nabout $($sc.Minutes) minutes`r`n$adm" 730 12 220 54 $global:C.Dim (F 8.5)))
        $b = NButton 'Run this' 760 74 180 34 $true ("Runs in this order: snapshot, live checks, Live Hunt, files, event logs, report.`r`nSensitive: " + $(if ($plan.Sensitive.Count) { ($plan.Sensitive | Select-Object -Unique) -join ', ' } else { 'none' })); $card.Controls.Add($b)
        $scId = $sc.Id; $scTitle = $sc.Title; $scPlan = $plan; $scAdm = $plan.AdminItems
        $b.Add_Click({
            $m = "Run '$scTitle'?`r`n`r`n$($scPlan.Tasks.Count) live checks, $($scPlan.Artifacts.Count) file groups, $($scPlan.Channels.Count) event logs.`r`n"
            if ($scAdm -and -not (Test-As4Admin)) { $m += "`r`n$scAdm item(s) need administrator and will be skipped (reported as SKIPPED).`r`n" }
            if ($scPlan.Sensitive.Count -and -not $skip.Checked) { $m += "`r`nThis includes private data: $((($scPlan.Sensitive | Select-Object -Unique) -join ', ')).`r`n" }
            $m += "`r`nNothing is changed on this machine. Output goes to the case folder."
            if (-not (Gui-Confirm $m $scTitle)) { return }
            Gui-Run { $r = Invoke-As4Scenario -Id $scId -SkipSensitive:$skip.Checked -OnProgress { param($i, $n, $t) Gui-Progress $i $n $t }
                Gui-ShowResults @($r.Results)
                if ($r.Hunt -and $r.Hunt.Verdict -and $global:G.LiveOut) { [void](Show-LhResult $global:G.LiveOut 'Live Hunt' $r.Hunt.Verdict $r.Hunt.Findings $r.Hunt.Next $r.Hunt.Blind $r.Hunt.Files $null); Show-Page 'Live Hunt'; Gui-Msg "Finished: $scTitle`r`n`r`nLive Hunt verdict: $($r.Hunt.Verdict.Verdict).`r`nThe case report is in 12_Reports." 'First Response' }
                else { Gui-Msg "Finished: $scTitle`r`n`r`nThe case report is in 12_Reports." 'First Response' } } $scTitle }.GetNewClosure())
        $y += 126
    }
    $p
}

function Build-ParsePage {
    $p = NPanel; foreach ($c in (NHeading 'Parse Collected Files' 'Turns what you collected into spreadsheets you can read: Prefetch, Amcache, Shimcache, shortcuts, Jump Lists, Recycle Bin, SRUM, the file table and event logs. It reads files already inside this case, never the live machine, and saves CSV in 15_Parsed.')) { $p.Controls.Add($c) }
    $cl = NCheckList 20 100 640 300; $p.Controls.Add($cl)
    $info = NLabel '' 680 100 330 140 $global:C.Dim (F 9); $p.Controls.Add($info)
    $br = NButton 'Parse selected' 680 250 160 34 $true 'Runs the bundled parsers on the matching files in this case.'; $p.Controls.Add($br)
    $ba = NButton 'Select all' 850 250 100 34; $p.Controls.Add($ba)
    $bo = NButton 'Open results folder' 680 294 200 32; $p.Controls.Add($bo)
    $state = @{ P = @() }
    $refresh = {
        $cl.Items.Clear(); $state.P = @(Get-As4Parsers); $lines = @()
        if (-not $global:Case) { $info.Text = 'No case is open.'; return }
        foreach ($x in $state.P) { $t = Get-As4Tool $x.Tool; $n = 0; try { $n = @(& $x.Find).Count } catch {}
            $tag = if (-not $t -or -not $t.Path) { 'parser missing' } elseif ($n) { "$n found" } else { 'nothing to parse yet' }
            [void]$cl.Items.Add(("{0}   [{1}]" -f $x.Name, $tag), [bool]($n -and $t -and $t.Path)) }
        $info.Text = "Tick what to parse. Items say how many matching files or folders this case holds.`r`n`r`nCollect first (Artifacts, Event Logs or KAPE), then parse." }.GetNewClosure()
    $p.Add_VisibleChanged({ if ($p.Visible) { & $refresh } }.GetNewClosure())
    $ba.Add_Click({ for ($i = 0; $i -lt $cl.Items.Count; $i++) { $cl.SetItemChecked($i, $true) } }.GetNewClosure())
    $br.Add_Click({ $ids = @(); for ($i = 0; $i -lt $cl.Items.Count; $i++) { if ($cl.GetItemChecked($i)) { $ids += $state.P[$i].Id } }
        if (-not $ids.Count) { Gui-Msg 'Tick at least one item.'; return }
        if (-not (Gui-Confirm "Parse $($ids.Count) item(s)?`r`nThey read files inside this case only and write CSV to 15_Parsed.")) { return }
        Gui-Run { Gui-ShowResults (Invoke-As4Parsers -Ids $ids -OnProgress { param($i, $n, $m) Gui-Progress $i $n $m }) } 'Parsing'; & $refresh }.GetNewClosure())
    $bo.Add_Click({ Start-Process explorer.exe -ArgumentList (ConvertTo-ArgString @((Get-CaseFolder 'Parsed'))) })
    $p
}
