# AS4 IR Tool - Windows Forms interface (ships with Windows PowerShell; nothing to install). ASCII only.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$global:C = @{
    Bg = [Drawing.Color]::FromArgb(17, 21, 20); Panel = [Drawing.Color]::FromArgb(24, 30, 28); Card = [Drawing.Color]::FromArgb(32, 40, 37)
    Line = [Drawing.Color]::FromArgb(48, 64, 58); Text = [Drawing.Color]::FromArgb(230, 232, 235); Dim = [Drawing.Color]::FromArgb(154, 164, 176)
    Accent = [Drawing.Color]::FromArgb(34, 160, 98); Warn = [Drawing.Color]::FromArgb(217, 164, 65); Ok = [Drawing.Color]::FromArgb(76, 175, 122); Bad = [Drawing.Color]::FromArgb(217, 107, 107)
    Input = [Drawing.Color]::FromArgb(12, 16, 15)
}
$global:G = @{ Busy = $false; Pages = @{}; Nav = @{}; Tip = $null; Log = $null; Bar = $null; Status = $null; Form = $null; Dash = $null }

function F { param([float]$s = 9, [string]$st = 'Regular') New-Object Drawing.Font('Segoe UI', $s, [Drawing.FontStyle]$st) }
function NLabel { param($t, $x, $y, $w = 300, $h = 20, $col = $null, $font = $null)
    $l = New-Object Windows.Forms.Label; $l.Text = $t; $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, $h)
    $l.ForeColor = $(if ($col) { $col } else { $global:C.Text }); $l.BackColor = [Drawing.Color]::Transparent; $l.Font = $(if ($font) { $font } else { F 9 }); $l.UseMnemonic = $false; $l }
function NButton { param($t, $x, $y, $w = 160, $h = 30, $primary = $false, $tip = '')
    $b = New-Object Windows.Forms.Button; $b.Text = $t; $b.Location = New-Object Drawing.Point($x, $y); $b.Size = New-Object Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = $(if ($primary) { $global:C.Accent } else { $global:C.Line }); $b.FlatAppearance.BorderSize = 1
    $b.BackColor = $(if ($primary) { $global:C.Accent } else { $global:C.Card }); $b.ForeColor = $(if ($primary) { [Drawing.Color]::White } else { $global:C.Text }); $b.Font = F 9; $b.Cursor = 'Hand'; $b.UseMnemonic = $false
    if ($tip) { $global:G.Tip.SetToolTip($b, $tip) }; $b }
function NText { param($x, $y, $w = 300, $text = '', $multi = $false, $h = 24)
    $t = New-Object Windows.Forms.TextBox; $t.Location = New-Object Drawing.Point($x, $y); $t.Size = New-Object Drawing.Size($w, $h); $t.Text = $text
    $t.BackColor = $global:C.Input; $t.ForeColor = $global:C.Text; $t.BorderStyle = 'FixedSingle'; $t.Font = F 9
    if ($multi) { $t.Multiline = $true; $t.ScrollBars = 'Vertical' }; $t }
function NCheck { param($t, $x, $y, $w = 300, $tip = '')
    $c = New-Object Windows.Forms.CheckBox; $c.Text = $t; $c.Location = New-Object Drawing.Point($x, $y); $c.Size = New-Object Drawing.Size($w, 22); $c.ForeColor = $global:C.Text; $c.BackColor = [Drawing.Color]::Transparent; $c.Font = F 9
    if ($tip) { $global:G.Tip.SetToolTip($c, $tip) }; $c }
function NCheckList { param($x, $y, $w, $h)
    $l = New-Object Windows.Forms.CheckedListBox; $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, $h); $l.BackColor = $global:C.Input; $l.ForeColor = $global:C.Text; $l.BorderStyle = 'FixedSingle'; $l.CheckOnClick = $true; $l.Font = F 9; $l }
function NCombo { param($x, $y, $w) $c = New-Object Windows.Forms.ComboBox; $c.Location = New-Object Drawing.Point($x, $y); $c.Size = New-Object Drawing.Size($w, 26); $c.DropDownStyle = 'DropDownList'; $c.BackColor = $global:C.Input; $c.ForeColor = $global:C.Text; $c.FlatStyle = 'Flat'; $c }
function NGrid { param($x, $y, $w, $h)
    $g = New-Object Windows.Forms.DataGridView; $g.Location = New-Object Drawing.Point($x, $y); $g.Size = New-Object Drawing.Size($w, $h)
    $g.BackgroundColor = $global:C.Bg; $g.GridColor = $global:C.Line; $g.BorderStyle = 'None'; $g.ReadOnly = $true; $g.AllowUserToAddRows = $false
    $g.EnableHeadersVisualStyles = $false; $g.ColumnHeadersDefaultCellStyle.BackColor = $global:C.Card; $g.ColumnHeadersDefaultCellStyle.ForeColor = $global:C.Text
    $g.DefaultCellStyle.BackColor = $global:C.Panel; $g.DefaultCellStyle.ForeColor = $global:C.Text; $g.DefaultCellStyle.SelectionBackColor = $global:C.Accent
    $g.RowHeadersVisible = $false; $g.AutoSizeColumnsMode = 'AllCells'; $g }
function NPanel { $p = New-Object Windows.Forms.Panel; $p.Dock = 'Fill'; $p.BackColor = $global:C.Bg; $p.AutoScroll = $true; $p.Visible = $false; $p }
function NHeading { param($t, $sub) @((NLabel $t 20 14 900 28 $global:C.Text (F 14 'Bold')), (NLabel $sub 21 44 1000 34 $global:C.Dim (F 9))) }
function New-BirdBox { param($x, $y, $h)
    $rows = $global:BirdRows; $w = ($rows | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum; $px = [Math]::Max(1, [int]($h / $rows.Count)); $bw = [int]($px * $w); $bh = [int]($px * $rows.Count)
    $bmp = New-Object Drawing.Bitmap($bw, $bh); $g = [Drawing.Graphics]::FromImage($bmp); $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(61, 220, 132)); $eye = New-Object Drawing.SolidBrush($global:C.Panel)
    for ($r = 0; $r -lt $rows.Count; $r++) { for ($c = 0; $c -lt $rows[$r].Length; $c++) { $ch = $rows[$r][$c]; if ($ch -eq 'X') { $g.FillRectangle($br, $c * $px, $r * $px, $px, $px) } elseif ($ch -eq 'e') { $g.FillRectangle($eye, $c * $px, $r * $px, $px, $px) } } }
    $g.Dispose(); $pb = New-Object Windows.Forms.PictureBox; $pb.Image = $bmp; $pb.SizeMode = 'AutoSize'; $pb.Location = New-Object Drawing.Point($x, ($y + [int](($h - $bh) / 2))); $pb.BackColor = [Drawing.Color]::Transparent; $pb }
function NSection { param($t, $x, $y, $w = 600) $l = NLabel $t $x $y $w 20 $global:C.Accent (F 9 'Bold'); $l }

# ---------- runtime helpers ----------
function Gui-Log { param($lvl, $msg)
    $rt = $global:G.Log; if (-not $rt) { return }
    $col = switch ($lvl) { 'ERROR' { $global:C.Bad } 'WARN' { $global:C.Warn } 'OK' { $global:C.Ok } default { $global:C.Dim } }
    $rt.SelectionStart = $rt.TextLength; $rt.SelectionColor = $col; $rt.AppendText(("{0}  {1,-5}  {2}`r`n" -f (Get-Date).ToString('HH:mm:ss'), $lvl, $msg)); $rt.ScrollToCaret() }
function Gui-Msg { param($t, $title = 'AS4 IR Tool', $icon = 'Information') [void][Windows.Forms.MessageBox]::Show($global:G.Form, $t, $title, 'OK', $icon) }
function Gui-Confirm { param($t, $title = 'Confirm', $high = $false) if ($env:AS4_AUTOCONFIRM -eq '1') { return $true }; ([Windows.Forms.MessageBox]::Show($global:G.Form, $t, $title, 'YesNo', $(if ($high) { 'Warning' } else { 'Question' })) -eq 'Yes') }

function Gui-Run {
    # Work runs on the UI thread while messages are pumped, so the window stays responsive and Cancel works.
    param([scriptblock]$Work, [string]$Title = 'Working')
    if ($global:G.Busy) { Gui-Msg 'An operation is already running. Wait for it or press Cancel.'; return }
    if (-not $global:Case) { Gui-Msg 'No case is open.' 'AS4 IR Tool' 'Warning'; return }
    $global:G.Busy = $true; $global:Cancel = $false; $global:G.Cancel.Enabled = $true; $global:G.Bar.Style = 'Marquee'; $global:G.Status.Text = $Title
    try { & $Work } catch { Gui-Log ERROR $_.Exception.Message; Gui-Msg $_.Exception.Message 'Error' 'Error' }
    finally { $global:G.Busy = $false; $global:G.Cancel.Enabled = $false; $global:G.Bar.Style = 'Blocks'; $global:G.Bar.Value = 0; $global:G.Status.Text = 'Ready'; Update-Overview }
}
function Gui-Progress { param($i, $n, $name) $global:G.Bar.Style = 'Blocks'; $global:G.Bar.Maximum = [Math]::Max($n, 1); $global:G.Bar.Value = [Math]::Min($i, $n); $global:G.Status.Text = "$i of ${n}: $name"; [Windows.Forms.Application]::DoEvents() }
function Gui-ShowResults { param($Res)
    $s = @($Res | Group-Object Status | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Gui-Log INFO "Finished: $s"
    foreach ($r in $Res) { if ($r.Status -ne 'OK') { Gui-Log WARN "$($r.Name): $($r.Status). $(@($r.Notes) -join ' ')" } } }

function Show-Page { param($name)
    foreach ($k in $global:G.Pages.Keys) { $global:G.Pages[$k].Visible = ($k -eq $name); $global:G.Nav[$k].BackColor = $(if ($k -eq $name) { $global:C.Card } else { $global:C.Panel }); $global:G.Nav[$k].ForeColor = $(if ($k -eq $name) { [Drawing.Color]::White } else { $global:C.Dim }) }
    if ($name -eq 'Overview') { Update-Overview }; if ($name -eq 'Tools') { Update-ToolsGrid } }

function Update-CaseHeader {
    if (-not $global:G.CaseLabel) { return }
    $global:G.CaseLabel.Text = $(if ($global:Case) { $global:Case.Id } else { '-' })
    $global:G.PathLabel.Text = $(if ($global:Case) { $global:Case.Dir } else { '' })
}

# ---------- case name dialog ----------
function Show-CaseDialog {
    param($Owner)
    $f = New-Object Windows.Forms.Form; $f.Text = 'AS4 IR Tool'; $f.Size = New-Object Drawing.Size(560, 430); $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.BackColor = $global:C.Bg; $f.ForeColor = $global:C.Text; $f.Font = F 9
    $f.Controls.Add((NLabel 'AS4 IR Tool' 24 18 400 30 $global:C.Text (F 16 'Bold')))
    $f.Controls.Add((NLabel 'Case name' 26 70 300 20 $global:C.Text (F 10 'Bold')))
    $tb = NText 26 94 490 '' $false 26; $tb.Font = F 11; $f.Controls.Add($tb)
    $hint = NLabel ('A folder with this name is created in: ' + $global:P.Output + "`r`nEverything collected or extracted is saved inside it.") 26 128 490 40 $global:C.Dim; $f.Controls.Add($hint)
    $f.Controls.Add((NLabel 'Existing cases' 26 178 300 20 $global:C.Text (F 9 'Bold')))
    $lb = New-Object Windows.Forms.ListBox; $lb.Location = New-Object Drawing.Point(26, 200); $lb.Size = New-Object Drawing.Size(490, 120); $lb.BackColor = $global:C.Input; $lb.ForeColor = $global:C.Text; $lb.BorderStyle = 'FixedSingle'
    foreach ($c in Get-As4Cases) { [void]$lb.Items.Add($c) }; $f.Controls.Add($lb)
    $lb.Add_SelectedIndexChanged({ if ($lb.SelectedItem) { $tb.Text = [string]$lb.SelectedItem } }.GetNewClosure())
    $err = NLabel '' 26 328 490 20 $global:C.Bad; $f.Controls.Add($err)
    $ok = NButton 'Start' 306 352 100 32 $true; $cn = NButton 'Exit' 416 352 100 32; $f.Controls.AddRange(@($ok, $cn))
    $f.AcceptButton = $ok; $f.CancelButton = $cn
    $ok.Add_Click({ try { $c = Start-As4Case $tb.Text; $f.Tag = 'ok'; $f.Close() } catch { $err.Text = $_.Exception.Message } }.GetNewClosure())
    $cn.Add_Click({ $f.Close() }.GetNewClosure())
    $lb.Add_DoubleClick({ if ($lb.SelectedItem) { $ok.PerformClick() } }.GetNewClosure())
    [void]$f.ShowDialog($Owner)
    ($f.Tag -eq 'ok')
}

# ---------- task-row page (Quick Response, Persistence) ----------
function New-TaskPage {
    param([string]$Title, [string]$Sub, [object[]]$Tasks, [string]$BtnPrefix = 'Collect', [bool]$HasFull = $true)
    $p = NPanel; foreach ($c in (NHeading $Title $Sub)) { $p.Controls.Add($c) }
    $boxes = @{}; $y = 84
    $bq = NButton 'Run quick set' 20 $y 130 30 $true 'Runs the items marked as the quick set (checked by default).'
    $ba = NButton 'Select all' 160 $y 100 30; $bn = NButton 'Clear' 270 $y 80 30; $br = NButton 'Run selected' 360 $y 130 30 $false 'Runs only the checked items.'
    $bf = NButton 'Run everything' 500 $y 130 30 $false 'Runs every item. Can take a long time and use disk space.'
    foreach ($b in $bq, $ba, $bn, $br) { $p.Controls.Add($b) }; if ($HasFull) { $p.Controls.Add($bf) }
    $list = New-Object Windows.Forms.Panel; $list.Location = New-Object Drawing.Point(20, 124); $list.Size = New-Object Drawing.Size(980, 480); $list.AutoScroll = $true; $list.BackColor = $global:C.Panel; $list.Anchor = 'Top,Left,Right,Bottom'
    $p.Controls.Add($list); $ry = 6
    foreach ($t in $Tasks) {
        $cb = NCheck '' 8 ($ry + 4) 22; $cb.Checked = [bool]$t.Quick
        $nm = $t.Name -replace '\s*\(.*?\)\s*$', ''
        $btn = NButton ("$BtnPrefix $nm") 34 $ry 330 28 $false ("{0}`r`nWhy: {1}`r`nAdministrator: {2}" -f $t.Desc, $t.Why, $t.Admin)
        $btn.TextAlign = 'MiddleLeft'
        $adm = switch ($t.Admin) { 'required' { 'Admin' } 'partial' { 'Admin (partial)' } default { '' } }
        $lab = NLabel $t.Desc 374 ($ry + 5) 560 20 $global:C.Dim (F 8.5)
        if ($adm) { $lab.Text = "[$adm] " + $t.Desc; $lab.ForeColor = $global:C.Warn }
        $list.Controls.AddRange(@($cb, $btn, $lab)); $boxes[$t.Id] = $cb
        $tk = $t; $btn.Add_Click({ Gui-Run { Gui-ShowResults (Invoke-As4Batch -Tasks @($tk) -OnProgress { param($i, $n, $x) Gui-Progress $i $n $x.Name }) } "Running $($tk.Name)" }.GetNewClosure())
        $ry += 34
    }
    $runSel = { param($tasks, $label) Gui-Run { Gui-ShowResults (Invoke-As4Batch -Tasks $tasks -Label $label -OnProgress { param($i, $n, $x) Gui-Progress $i $n $x.Name }) } $label }.GetNewClosure()
    $bq.Add_Click({ $sel = @($Tasks | Where-Object Quick); if (Gui-Confirm "Run $($sel.Count) tasks and save the output in the case folder?") { & $runSel $sel 'quick set' } }.GetNewClosure())
    $br.Add_Click({ $sel = @($Tasks | Where-Object { $boxes[$_.Id].Checked }); if (-not $sel.Count) { Gui-Msg 'Nothing is checked.'; return }; if (Gui-Confirm "Run $($sel.Count) selected tasks?") { & $runSel $sel 'selection' } }.GetNewClosure())
    $bf.Add_Click({ if (Gui-Confirm "This runs all $($Tasks.Count) tasks and may take a while and use disk space. Free space on this drive: $((Get-As4Host).DriveFreeGB) GB. Continue?" 'Run everything' $true) { & $runSel @($Tasks) 'all tasks' } }.GetNewClosure())
    $ba.Add_Click({ foreach ($k in $boxes.Keys) { $boxes[$k].Checked = $true } }.GetNewClosure())
    $bn.Add_Click({ foreach ($k in $boxes.Keys) { $boxes[$k].Checked = $false } }.GetNewClosure())
    $p }

# ---------- pages ----------
function Update-Overview {
    $d = $global:G.Dash; if (-not $d) { return }
    $h = Get-As4Host
    $d.Work.Text = "$($h.Computer)`r`n$($h.OS)`r`n$($h.Arch), PowerShell $($h.PowerShell)`r`n$($h.User)"
    $d.Case.Text = $(if ($global:Case) { "$($global:Case.Id)`r`n$($global:Case.Dir)`r`nFree space: $($h.DriveFreeGB) GB" } else { 'No case open.' })
    $d.Adm.Text = $(if ($h.Admin) { 'Running as administrator' } else { 'Standard user - admin-only items will be skipped' }); $d.Adm.ForeColor = $(if ($h.Admin) { $global:C.Ok } else { $global:C.Warn })
    $d.Tools.Text = (Get-As4Tools | ForEach-Object { '{0,-36} {1}' -f $_.Name, $_.Status }) -join "`r`n"
    if ($global:Case) { $s = Get-As4Summary $global:Case.Dir; $d.Sum.Text = (($s.PSObject.Properties | ForEach-Object { "$($_.Name): $($_.Value)" }) -join '    ') } else { $d.Sum.Text = '' }
}
function Build-Overview {
    $p = NPanel; foreach ($c in (NHeading 'Overview' 'Current case, this workstation and the tools found in the tools folder.')) { $p.Controls.Add($c) }
    $d = @{}
    $mk = { param($title, $x, $y, $w, $h) $card = New-Object Windows.Forms.Panel; $card.Location = New-Object Drawing.Point($x, $y); $card.Size = New-Object Drawing.Size($w, $h); $card.BackColor = $global:C.Panel
        $card.Controls.Add((NLabel $title 14 10 ($w - 28) 18 $global:C.Accent (F 9 'Bold')))
        $t = NLabel '' 14 34 ($w - 28) ($h - 42) $global:C.Text (F 9.5); $card.Controls.Add($t); $p.Controls.Add($card); $t }
    $d.Work = & $mk 'This workstation' 20 90 480 110
    $d.Case = & $mk 'Case' 510 90 490 110
    $d.Adm = & $mk 'Privileges' 20 210 480 70; $d.Adm.Font = F 10.5 'Bold'
    $d.Sum = & $mk 'Operations in this case' 510 210 490 70
    $d.Tools = & $mk 'Tools' 20 290 480 270; $d.Tools.Font = New-Object Drawing.Font('Consolas', 9)
    $n = & $mk 'Notes' 510 290 490 270
    $n.Text = "Collection is read-only. Nothing is deleted, stopped or quarantined.`r`nNothing is downloaded or installed on the target.`r`nLive commands and memory capture still touch the running system; see the README.`r`nRule and heuristic matches are leads for review, not conclusions."
    $n.ForeColor = $global:C.Dim
    $global:G.Dash = $d; $p }

function Build-EvtxPage {
    $p = NPanel; foreach ($c in (NHeading 'Event Logs' 'Exports channels with wevtutil. Without filters you get the original EVTX (raw_evtx). With a time range or event IDs the result is a filtered copy (filtered_evtx). Logs are never cleared or changed.')) { $p.Controls.Add($c) }
    $chs = @(Get-As4EvtxChannels); $cl = NCheckList 20 90 640 440; foreach ($c in $chs) { [void]$cl.Items.Add(("{0}{1}  [{2}]" -f $(if ($c.Admin) { '(admin) ' } else { '' }), $c.Name, $c.Group), ($c.Group -in 'Core', 'PowerShell')) }; $p.Controls.Add($cl)
    $desc = NLabel '' 680 90 330 70 $global:C.Dim; $p.Controls.Add($desc)
    $cl.Add_SelectedIndexChanged({ if ($cl.SelectedIndex -ge 0) { $desc.Text = $chs[$cl.SelectedIndex].Desc } }.GetNewClosure())
    $p.Controls.Add((NLabel 'Event IDs (comma separated, optional)' 680 170 330)); $ids = NText 680 192 330; $p.Controls.Add($ids)
    $p.Controls.Add((NLabel 'From, UTC (2026-10-01T00:00:00)' 680 226 330)); $fr = NText 680 248 330; $p.Controls.Add($fr)
    $p.Controls.Add((NLabel 'To, UTC' 680 282 330)); $to = NText 680 304 330; $p.Controls.Add($to)
    $bx = NButton 'Export selected' 680 346 160 32 $true 'Checks that each channel exists, then runs wevtutil epl. Security needs administrator.'; $p.Controls.Add($bx)
    $ba = NButton 'Select all' 850 346 100 32; $p.Controls.Add($ba); $ba.Add_Click({ for ($i = 0; $i -lt $cl.Items.Count; $i++) { $cl.SetItemChecked($i, $true) } }.GetNewClosure())
    $bx.Add_Click({
        $sel = @(); for ($i = 0; $i -lt $cl.Items.Count; $i++) { if ($cl.GetItemChecked($i)) { $sel += $chs[$i].Name } }
        if (-not $sel.Count) { Gui-Msg 'Select at least one channel.'; return }
        try { $q = New-As4EvtxQuery -StartUtc $(if ($fr.Text) { [datetime]::Parse($fr.Text, $null, 'AdjustToUniversal,AssumeUniversal') }) -EndUtc $(if ($to.Text) { [datetime]::Parse($to.Text, $null, 'AdjustToUniversal,AssumeUniversal') }) -EventIds $ids.Text } catch { Gui-Msg $_.Exception.Message 'Invalid filter' 'Warning'; return }
        $m = if ($q) { "Filtered export (a subset, not the original log):`r`n$q" } else { 'Original EVTX export.' }
        if (Gui-Confirm "Export $($sel.Count) channels?`r`n$m") { Gui-Run { $o = Export-As4Evtx -Channels $sel -Query $q -OnProgress { param($i, $n, $c) Gui-Progress $i $n $c }; Gui-Log OK "Exported $(@($o).Count) file(s)" } 'Exporting event logs'; if (Gui-Confirm 'Optional: run a Quick Scan on the exported logs now?' 'Quick Scan') { Show-Page 'Quick Scan' } } }.GetNewClosure())
    $p }

function Build-QuickScanPage {
    $p = NPanel; foreach ($c in (NHeading 'Quick Scan' 'Optional. Point it at a folder of event logs (this case, any folder, or this computer) and get a fast answer: is anything here worth a closer look? It uses the bundled Hayabusa rules, runs entirely on this machine and downloads nothing.')) { $p.Controls.Add($c) }
    $hi = Get-HayabusaInfo
    if (-not $hi.Runnable) { $p.Controls.Add((NLabel 'Hayabusa is not available, so Quick Scan cannot run.' 20 90 900 20 $global:C.Bad)); return $p }
    $state = @{ Path = ''; Res = $null }
    $p.Controls.Add((NLabel 'Where are the logs?' 20 90 300 20 $global:C.Text (F 9 'Bold'))); $lc = NCombo 20 112 360; [void]$lc.Items.AddRange(@('Everything in this case (all .evtx found)', 'Another folder...', 'One log file...', 'This computer (live logs)')); $lc.SelectedIndex = 0; $p.Controls.Add($lc)
    $info = NLabel '' 392 116 640 36 $global:C.Dim (F 8.5); $p.Controls.Add($info)
    $fast = NCheck 'Fast mode (medium and above only)' 20 148 300 'Skips low and informational rules. Quicker, and less detail on logons.'; $p.Controls.Add($fast)
    $so = NCheck 'Second opinion with Chainsaw (Sigma rules)' 330 148 340 'Also runs Chainsaw on the same logs and compares.'; $p.Controls.Add($so)
    if (-not (Get-ChainsawInfo).Runnable) { $so.Enabled = $false }
    $bs = NButton 'Scan now' 700 142 150 36 $true 'Runs the rules and builds the verdict. Results are saved in 12_Reports (HTML and text) and 11_Hayabusa_Analysis.'; $p.Controls.Add($bs)
    $out = New-Object Windows.Forms.Panel; $out.Location = New-Object Drawing.Point(20, 190); $out.Size = New-Object Drawing.Size(1000, 40); $out.BackColor = $global:C.Bg; $out.Anchor = 'Top,Left,Right'; $p.Controls.Add($out)
    $getSrc = { switch ($lc.SelectedIndex) { 0 { @{ Kind = 'case' } } 1 { @{ Kind = 'directory'; Path = $state.Path } } 2 { @{ Kind = 'file'; Path = $state.Path } } default { @{ Kind = 'live' } } } }.GetNewClosure()
    $refresh = { switch ($lc.SelectedIndex) {
        0 { $d = @(Find-As4LogDirs $global:Case.Dir); if ($d.Count) { $n = ($d | Measure-Object Files -Sum).Sum; $mb = [math]::Round((($d | Measure-Object Bytes -Sum).Sum) / 1MB); $names = @($d | ForEach-Object { $_.Names }); $ty = (Get-QsLogTypes $names).GetEnumerator() | Where-Object Value | ForEach-Object { $_.Key }; $info.Text = "$n log files ($mb MB) in $($d.Count) folder(s). Types: $($ty -join ', ')." } else { $info.Text = 'No .evtx files in this case yet. Export them on the Event Logs page, collect with KAPE, or choose another folder.' } }
        3 { $info.Text = 'Reads C:\Windows\System32\winevt\Logs directly. Administrator is needed for the Security log.' }
        default { $info.Text = $state.Path } } }.GetNewClosure()
    $lc.Add_SelectedIndexChanged({
        if ($lc.SelectedIndex -eq 1) { $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $state.Path = $d.SelectedPath } else { $lc.SelectedIndex = 0; return } }
        if ($lc.SelectedIndex -eq 2) { $d = New-Object Windows.Forms.OpenFileDialog; $d.Filter = 'Event logs|*.evtx|All|*.*'; if ($d.ShowDialog() -eq 'OK') { $state.Path = $d.FileName } else { $lc.SelectedIndex = 0; return } }
        & $refresh }.GetNewClosure()); & $refresh
    $p.Add_VisibleChanged({ if ($p.Visible) { & $refresh } }.GetNewClosure())
    $render = {
        param($res)
        $out.Controls.Clear(); $a = $res.Analysis
        if (-not $a) { $out.Controls.Add((NLabel "The scan did not complete: $(@($res.Notes) -join ' ')" 0 6 980 40 $global:C.Bad)); $out.Height = 60; return }
        $bc = switch ($a.Color) { 'green' { [Drawing.Color]::FromArgb(46, 125, 79) } 'yellow' { [Drawing.Color]::FromArgb(154, 123, 23) } 'orange' { [Drawing.Color]::FromArgb(180, 96, 26) } 'red' { [Drawing.Color]::FromArgb(169, 50, 50) } default { [Drawing.Color]::FromArgb(122, 31, 31) } }
        $y = 0; $ban = New-Object Windows.Forms.Panel; $ban.Location = New-Object Drawing.Point(0, 0); $ban.Size = New-Object Drawing.Size(980, 82); $ban.BackColor = $bc; $ban.Anchor = 'Top,Left,Right'; $out.Controls.Add($ban)
        $ban.Controls.Add((NLabel "$($a.Verdict)   (score $($a.Score))" 14 8 940 30 ([Drawing.Color]::White) (F 16 'Bold'))); $ban.Controls.Add((NLabel $a.VerdictText 16 42 950 36 ([Drawing.Color]::White) (F 9))); $y = 92
        $cnt = ($a.Counts.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join '     '; $out.Controls.Add((NLabel "Findings:  $cnt" 0 $y 980 20 $global:C.Text (F 9.5 'Bold'))); $y += 22
        if ($a.Coverage) { $out.Controls.Add((NLabel "Logs: $($a.Coverage.FileCount) files, $($a.Coverage.Events) events, $(Format-QsDate $a.Coverage.First)  to  $(Format-QsDate $a.Coverage.Last)" 0 $y 980 18 $global:C.Dim (F 8.5))); $y += 20 }
        if ($a.Window) { $out.Controls.Add((NLabel "Incident window (serious findings): $(Format-QsDate $a.Window.From)  to  $(Format-QsDate $a.Window.To)  ($($a.Window.Hours) h)" 0 $y 980 18 $global:C.Warn (F 9 'Bold'))); $y += 24 } else { $y += 4 }
        $out.Controls.Add((NSection 'WHY THIS VERDICT' 0 $y 400)); $y += 20; $why = if ($a.Reasons.Count) { ($a.Reasons | ForEach-Object { "+$($_.Points)   $($_.Text)" }) -join "`r`n" } else { 'No scoring reasons.' }; $h = 18 * [math]::Max(1, ($a.Reasons.Count + 1)); $out.Controls.Add((NLabel $why 0 $y 980 $h $global:C.Text (F 8.5))); $y += $h + 8
        $out.Controls.Add((NSection 'ATTACK CHAIN (MITRE tactics seen in the findings)' 0 $y 600)); $y += 22; $x = 0
        foreach ($c in $a.Chain) { $pn = New-Object Windows.Forms.Panel; $pn.Size = New-Object Drawing.Size(124, 44); $pn.Location = New-Object Drawing.Point($x, $y); $pn.BackColor = $(if ($c.Serious) { [Drawing.Color]::FromArgb(92, 44, 44) } elseif ($c.All) { [Drawing.Color]::FromArgb(70, 62, 36) } else { $global:C.Panel })
            $pn.Controls.Add((NLabel $c.Name 4 3 118 16 $global:C.Dim (F 7.5))); $pn.Controls.Add((NLabel "$($c.All)" 4 18 118 22 $(if ($c.Serious) { [Drawing.Color]::FromArgb(255, 138, 138) } elseif ($c.All) { $global:C.Warn } else { $global:C.Line }) (F 12 'Bold'))); $out.Controls.Add($pn); $x += 128; if ($x + 124 -gt 980) { $x = 0; $y += 48 } }
        if ($x -ne 0) { $y += 48 }; $y += 6
        if ($a.Hist.Count) { $out.Controls.Add((NSection 'WHEN (red = serious, blue = other findings)' 0 $y 600)); $y += 20
            $hp = New-Object Windows.Forms.Panel; $hp.Location = New-Object Drawing.Point(0, $y); $hp.Size = New-Object Drawing.Size(980, 70); $hp.BackColor = $global:C.Panel; $hist = $a.Hist; $mx = [math]::Max(1, (@($hist | ForEach-Object { $_.Serious + $_.Other }) | Measure-Object -Maximum).Maximum)
            $hp.Add_Paint({ param($s, $e) $g = $e.Graphics; $w = [math]::Max(3, [math]::Min(14, [int](960 / [math]::Max(1, $hist.Count)))); $i = 0
                foreach ($b in $hist) { $x0 = 6 + $i * $w; $h2 = [int](60 * $b.Other / $mx); $h1 = [int](60 * $b.Serious / $mx); $g.FillRectangle((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(90, 122, 168))), $x0, 66 - $h2, $w - 1, $h2); $g.FillRectangle((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(224, 108, 108))), $x0, 66 - $h2 - $h1, $w - 1, $h1); $i++ } }.GetNewClosure())
            $out.Controls.Add($hp); $y += 78 }
        $out.Controls.Add((NSection 'TOP FINDINGS' 0 $y 400)); $y += 20
        $g = NGrid 0 $y 980 170; $g.Anchor = 'Top,Left,Right'; $dt = New-Object Data.DataTable; foreach ($c in 'Level', 'What was detected', 'Hits', 'First', 'Last') { [void]$dt.Columns.Add($c) }
        foreach ($r in ($a.Rules | Select-Object -First 40)) { [void]$dt.Rows.Add($r.Sev, $r.Title, $r.Count, (Format-QsDate $r.First), (Format-QsDate $r.Last)) }; $g.DataSource = $dt
        $g.Add_CellFormatting({ param($s, $e) if ($e.RowIndex -ge 0) { $v = [string]$s.Rows[$e.RowIndex].Cells['Level'].Value; $c = switch ($v) { 'critical' { [Drawing.Color]::FromArgb(112, 38, 38) } 'high' { [Drawing.Color]::FromArgb(122, 70, 34) } 'medium' { [Drawing.Color]::FromArgb(104, 92, 36) } 'low' { [Drawing.Color]::FromArgb(38, 66, 104) } default { $null } }; if ($c) { $e.CellStyle.BackColor = $c; $e.CellStyle.ForeColor = [Drawing.Color]::White } } })
        $out.Controls.Add($g); $y += 180
        $inv = { param($x) if ($x.Count) { ($x | ForEach-Object { "$($_.Value) ($($_.Count))" }) -join ',  ' } else { '-' } }
        $out.Controls.Add((NSection 'MOST INVOLVED' 0 $y 400)); $y += 20; $out.Controls.Add((NLabel ("Hosts:  " + (& $inv $a.Hosts) + "`r`nAccounts:  " + (& $inv $a.Users) + "`r`nAddresses:  " + (& $inv $a.Ips)) 0 $y 980 56 $global:C.Text (F 8.5))); $y += 62
        if ($a.Second) { $out.Controls.Add((NSection 'SECOND OPINION (Chainsaw with Sigma rules)' 0 $y 600)); $y += 20; $out.Controls.Add((NLabel $a.Second.Summary 0 $y 980 36 $global:C.Text (F 8.5))); $y += 40 }
        $out.Controls.Add((NSection 'BLIND SPOTS - what this scan could not see' 0 $y 600)); $y += 20; $bt = if ($a.Blind.Count) { ($a.Blind | ForEach-Object { "- $_" }) -join "`r`n" } else { '- none identified' }; $bh = 18 * [math]::Max(1, $a.Blind.Count); $out.Controls.Add((NLabel $bt 0 $y 980 $bh $global:C.Warn (F 8.5))); $y += $bh + 8
        $out.Controls.Add((NSection 'NEXT STEPS' 0 $y 400)); $y += 20; $i = 0; $nt = ($a.Next | ForEach-Object { $i++; "$i. $_" }) -join "`r`n"; $nh = 18 * [math]::Max(1, $a.Next.Count) + 6; $out.Controls.Add((NLabel $nt 0 $y 980 $nh $global:C.Text (F 8.5))); $y += $nh + 8
        $b1 = NButton 'Open summary (HTML)' 0 $y 180 32 $true; $b2 = NButton 'Open summary (text)' 190 $y 170 32; $b3 = NButton 'Open results folder' 370 $y 170 32; $b4 = NButton 'Investigate in Hayabusa' 550 $y 190 32
        $hp2 = $a.HtmlPath; $tp2 = $a.TextPath
        $b1.Add_Click({ Start-Process $hp2 }.GetNewClosure()); $b2.Add_Click({ Start-Process $tp2 }.GetNewClosure()); $b3.Add_Click({ Start-Process explorer.exe -ArgumentList (ConvertTo-ArgString @((Get-CaseFolder 'Rep'))) }); $b4.Add_Click({ Show-Page 'Hayabusa' })
        $out.Controls.AddRange(@($b1, $b2, $b3, $b4)); $y += 44
        $out.Controls.Add((NLabel 'Rule matches are leads for review, not proof of compromise. No match is not proof of a clean machine.' 0 $y 980 18 $global:C.Dim (F 8))); $y += 24
        $out.Height = $y }.GetNewClosure()
    $bs.Add_Click({
        $src = & $getSrc; if ($src.Kind -in 'directory', 'file' -and -not $src.Path) { return }
        if (-not (Gui-Confirm "Run Quick Scan on: $($info.Text)`r`nThis reads the logs only; nothing is changed or sent anywhere.")) { return }
        Gui-Run { $res = Invoke-QuickScan -Source $src -Fast:$fast.Checked -SecondOpinion:($so.Checked -and $so.Enabled) -OnProgress { param($i, $n, $m) Gui-Progress $i $n $m }; Gui-ShowResults @($res); & $render $res } 'Quick Scan' }.GetNewClosure())
    $p }
function Build-HayabusaPage {
    $p = NPanel; foreach ($c in (NHeading 'Hayabusa' 'Choose what you want to find. AS4 runs the matching rules on the logs and lists the answer in plain words. Every option is on the Hayabusa Advanced page.')) { $p.Controls.Add($c) }
    $st = NLabel '' 20 80 1000 20 $global:C.Dim; $p.Controls.Add($st)
    $hi = Get-HayabusaInfo
    if (-not $hi.Present) { $st.Text = 'Hayabusa was not found in tools\Hayabusa.'; $st.ForeColor = $global:C.Bad; return $p }
    if (-not $hi.Runnable) { $st.Text = "Hayabusa cannot run: $($hi.BlockReason)"; $st.ForeColor = $global:C.Bad; return $p }
    $st.Text = "$($hi.Version) - $($hi.RuleFiles) rules"; $st.ForeColor = $global:C.Ok
    $scen = @(Get-HayabusaScenarios); $state = @{ Rows = @(); Report = $null; Path = ''; Findings = @() }
    # --- the three simple questions
    $p.Controls.Add((NLabel 'Which logs?' 20 108 300 20 $global:C.Text (F 9 'Bold'))); $lc = NCombo 20 130 330; [void]$lc.Items.AddRange(@('Event logs exported in this case', 'Another folder...', 'Another file...', 'This computer (live logs)')); $lc.SelectedIndex = 0; $p.Controls.Add($lc)
    $lp = NLabel '' 360 134 640 20 $global:C.Dim (F 8.5); $p.Controls.Add($lp)
    $p.Controls.Add((NLabel 'When?' 20 166 200 20 $global:C.Text (F 9 'Bold'))); $tc = NCombo 20 188 200; [void]$tc.Items.AddRange(@('All time', 'Last 24 hours', 'Last 7 days', 'Last 30 days', 'Custom dates')); $tc.SelectedIndex = 0; $p.Controls.Add($tc)
    $df = NText 230 188 100 ''; $dt2 = NText 340 188 100 ''; $df.Visible = $false; $dt2.Visible = $false; $p.Controls.Add($df); $p.Controls.Add($dt2)
    $dh = NLabel 'from / to (2026-10-01)' 230 168 220 18 $global:C.Dim (F 8); $dh.Visible = $false; $p.Controls.Add($dh)
    $tc.Add_SelectedIndexChanged({ $v = ($tc.SelectedItem -eq 'Custom dates'); $df.Visible = $v; $dt2.Visible = $v; $dh.Visible = $v }.GetNewClosure())
    $p.Controls.Add((NLabel 'How serious?' 470 166 200 20 $global:C.Text (F 9 'Bold'))); $sc2 = NCombo 470 188 260; [void]$sc2.Items.AddRange(@('Show everything', 'Medium and above', 'High and critical only')); $sc2.SelectedIndex = 0; $p.Controls.Add($sc2)
    $hc = NCheck 'Also save an HTML report' 750 190 250 'Adds a summary page with charts for the timeline scenarios.'; $hc.Checked = $true; $p.Controls.Add($hc)
    $getIn = {
        switch ($lc.SelectedIndex) {
            0 { @{ Kind = 'directory'; Path = (Join-Path $global:Case.Dir '05_Event_Logs\raw_evtx') } }
            1 { @{ Kind = 'directory'; Path = $state.Path } }
            2 { @{ Kind = 'file'; Path = $state.Path } }
            default { @{ Kind = 'live'; Path = '' } } } }.GetNewClosure()
    # --- scenario cards
    $p.Controls.Add((NLabel 'What do you want to find?' 20 226 400 22 $global:C.Text (F 10 'Bold')))
    $ba = NButton 'Select all' 640 222 90 28; $bn = NButton 'Clear' 736 222 70 28; $br = NButton 'Run selected' 816 220 140 32 $true 'Runs every ticked question on the chosen logs. Results are saved in 11_Hayabusa_Analysis.'; $p.Controls.AddRange(@($ba, $bn, $br))
    $cards = New-Object Windows.Forms.Panel; $cards.Location = New-Object Drawing.Point(20, 254); $cards.Size = New-Object Drawing.Size(990, 280); $cards.AutoScroll = $true; $cards.BackColor = $global:C.Panel; $cards.Anchor = 'Top,Left,Right'; $p.Controls.Add($cards)
    $boxes = @{}; $warns = @{}; $y = 6; $grp = ''
    foreach ($sx in $scen) {
        if ($sx.Group -ne $grp) { $grp = $sx.Group; $cards.Controls.Add((NLabel $grp.ToUpper() 12 $y 500 18 $global:C.Accent (F 8 'Bold'))); $y += 22 }
        $cb = NCheck '' 10 ($y + 2) 22; $cards.Controls.Add($cb); $boxes[$sx.Id] = $cb
        $cards.Controls.Add((NLabel $sx.Title 36 $y 600 20 $global:C.Text (F 9.5 'Bold')))
        $cards.Controls.Add((NLabel $sx.Description 36 ($y + 20) 800 18 $global:C.Dim (F 8.5)))
        $n = Get-ScenarioRuleCount $sx; $cov = if ($n -gt 0) { "$n rules" } elseif ($sx.Options.'include-tag') { 'by MITRE tag' } else { '' }
        $cards.Controls.Add((NLabel $cov 840 ($y + 2) 130 18 $global:C.Dim (F 8)))
        $w = NLabel '' 640 ($y + 2) 190 18 $global:C.Warn (F 8); $w.TextAlign = 'MiddleRight'; $cards.Controls.Add($w); $warns[$sx.Id] = $w
        $y += 46 }
    $refreshWarn = { $in = & $getIn; foreach ($sx in $scen) { $m = @(Test-ScenarioLogs $sx $in); $warns[$sx.Id].Text = $(if ($m.Count) { 'no ' + ($m -join '/') + ' log here' } else { '' }) } }.GetNewClosure()
    $setPath = { switch ($lc.SelectedIndex) { 0 { $lp.Text = (Join-Path $global:Case.Dir '05_Event_Logs\raw_evtx') } 3 { $lp.Text = 'Reads C:\Windows\System32\winevt\Logs directly (administrator needed for Security).' } default { $lp.Text = $state.Path } }; & $refreshWarn }.GetNewClosure()
    $lc.Add_SelectedIndexChanged({
        if ($lc.SelectedIndex -eq 1) { $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $state.Path = $d.SelectedPath } else { $lc.SelectedIndex = 0; return } }
        if ($lc.SelectedIndex -eq 2) { $d = New-Object Windows.Forms.OpenFileDialog; $d.Filter = 'Event logs|*.evtx|All|*.*'; if ($d.ShowDialog() -eq 'OK') { $state.Path = $d.FileName } else { $lc.SelectedIndex = 0; return } }
        & $setPath }.GetNewClosure()); & $setPath
    $ba.Add_Click({ foreach ($k in $boxes.Keys) { $boxes[$k].Checked = $true } }.GetNewClosure()); $bn.Add_Click({ foreach ($k in $boxes.Keys) { $boxes[$k].Checked = $false } }.GetNewClosure())
    # --- results
    $sum = NLabel 'Results appear here.' 20 546 990 22 $global:C.Text (F 10 'Bold'); $p.Controls.Add($sum)
    $sum2 = NLabel '' 20 570 990 34 $global:C.Dim (F 8.5); $p.Controls.Add($sum2)
    $fs = NCombo 20 606 170; [void]$fs.Items.AddRange(@('All severities', 'Critical only', 'High and above', 'Medium and above', 'Low and above')); $fs.SelectedIndex = 0; $p.Controls.Add($fs)
    $ft = NText 200 607 300 ''; $p.Controls.Add($ft); $p.Controls.Add((NLabel 'search' 506 610 60 18 $global:C.Dim (F 8)))
    $bo = NButton 'Open results folder' 580 604 160 28; $bhtml = NButton 'Open HTML report' 748 604 150 28; $bhtml.Enabled = $false; $p.Controls.AddRange(@($bo, $bhtml))
    $grid = NGrid 20 640 990 260; $grid.Anchor = 'Top,Left,Right'; $grid.AutoSizeColumnsMode = 'None'; $p.Controls.Add($grid)
    $grid.Add_CellFormatting({ param($s, $e) if ($e.RowIndex -ge 0 -and $s.Columns.Count -gt 2) { $v = [string]$s.Rows[$e.RowIndex].Cells['Severity'].Value
        $c = switch ($v) { 'critical' { [Drawing.Color]::FromArgb(112, 38, 38) } 'high' { [Drawing.Color]::FromArgb(122, 70, 34) } 'medium' { [Drawing.Color]::FromArgb(104, 92, 36) } 'low' { [Drawing.Color]::FromArgb(38, 66, 104) } default { $null } }
        if ($c) { $e.CellStyle.BackColor = $c; $e.CellStyle.ForeColor = [Drawing.Color]::White } } })
    $apply = { if (-not $grid.DataSource) { return }; $dv = $grid.DataSource.DefaultView; $f = @()
        switch ($fs.SelectedIndex) { 1 { $f += "Severity IN ('critical')" } 2 { $f += "Severity IN ('critical','high')" } 3 { $f += "Severity IN ('critical','high','medium')" } 4 { $f += "Severity IN ('critical','high','medium','low')" } }
        $q = ($ft.Text -replace "[\[\]\*%']", '').Trim(); if ($q) { $f += "([What happened] LIKE '%$q%' OR Details LIKE '%$q%' OR Computer LIKE '%$q%' OR Scenario LIKE '%$q%')" }
        try { $dv.RowFilter = ($f -join ' AND ') } catch {} }.GetNewClosure()
    $fs.Add_SelectedIndexChanged($apply); $ft.Add_TextChanged($apply)
    $bo.Add_Click({ if ($global:Case) { Start-Process explorer.exe -ArgumentList (ConvertTo-ArgString @((Get-CaseFolder 'Hay'))) } })
    $bhtml.Add_Click({ if ($state.Report -and (Test-Path -LiteralPath $state.Report)) { Start-Process $state.Report } }.GetNewClosure())
    # --- run
    $br.Add_Click({
        $sel = @($scen | Where-Object { $boxes[$_.Id].Checked }); if (-not $sel.Count) { Gui-Msg 'Tick at least one question.'; return }
        $in = & $getIn
        if ($in.Kind -in 'directory', 'file' -and -not (Test-Path -LiteralPath $in.Path)) {
            if ($lc.SelectedIndex -eq 0) {
                if (Gui-Confirm "No event logs have been exported in this case yet.`r`nExport the main logs now (System, Security, PowerShell, Defender, Task Scheduler, RDP, WinRM, WMI, Sysmon if present)? Security needs administrator." 'Export logs first') {
                    $names = @('System', 'Application', 'Security', 'Windows PowerShell', 'Microsoft-Windows-PowerShell/Operational', 'Microsoft-Windows-Sysmon/Operational', 'Microsoft-Windows-Windows Defender/Operational', 'Microsoft-Windows-TaskScheduler/Operational', 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational', 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational', 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational', 'Microsoft-Windows-TerminalServices-RDPClient/Operational', 'Microsoft-Windows-WinRM/Operational', 'Microsoft-Windows-WMI-Activity/Operational')
                    Gui-Run { [void](Export-As4Evtx -Channels $names -OnProgress { param($i, $n, $c) Gui-Progress $i $n $c }) } 'Exporting event logs'; & $refreshWarn }
                if (-not (Test-Path -LiteralPath $in.Path)) { return } }
            else { Gui-Msg 'That path does not exist.'; return } }
        $time = switch ($tc.SelectedIndex) { 1 { '24h' } 2 { '7d' } 3 { '30d' } 4 { 'custom' } default { 'all' } }
        $sev = switch ($sc2.SelectedIndex) { 1 { 'medium' } 2 { 'high' } default { 'all' } }
        $miss = @($sel | Where-Object { @(Test-ScenarioLogs $_ $in).Count }); $msg = "Run $($sel.Count) question(s)?"
        if ($miss.Count) { $msg += "`r`n`r`nThese need logs that are not in the chosen input, so they will probably find nothing:`r`n - " + (($miss | ForEach-Object { $_.Title }) -join "`r`n - ") }
        if (-not (Gui-Confirm $msg 'Hayabusa')) { return }
        Gui-Run {
            $all = @(); $perScen = @(); $i = 0; $state.Report = $null
            foreach ($sx in $sel) { $i++; Gui-Progress $i $sel.Count $sx.Title
                try { $res = Invoke-HayabusaScenario -Scenario $sx -InSpec $in -Time $time -From $df.Text -To $dt2.Text -Severity $sev -Html $hc.Checked } catch { Gui-Log ERROR "$($sx.Title): $($_.Exception.Message)"; continue }
                Gui-ShowResults @($res); $f = Get-HayabusaFindings $res
                foreach ($x in $f.Rows) { $all += [pscustomobject]@{ Scenario = $sx.Title; Time = $x.Time; Severity = $x.Severity; 'What happened' = $x.What; Computer = $x.Computer; Where = $x.Where; Details = $x.Details } }
                $perScen += [pscustomobject]@{ Title = $sx.Title; Status = $res.Status; Count = $f.Total; Cmd = $sx.Command }
                if (-not $state.Report) { $rp = @($res.Destination | Where-Object { $_ -like '*report.html' } | Select-Object -First 1); if ($rp.Count) { $state.Report = Join-Path $global:Case.Dir $rp[0] } } }
            $d = New-Object Data.DataTable; foreach ($c in 'Scenario', 'Time', 'Severity', 'What happened', 'Computer', 'Where', 'Details') { [void]$d.Columns.Add($c) }
            foreach ($x in ($all | Sort-Object @{ e = { $global:HaySevRank[$_.Severity] }; Descending = $true }, Time | Select-Object -First 8000)) { $row = $d.NewRow(); foreach ($c in $d.Columns) { $row[$c.ColumnName] = [string]$x.($c.ColumnName) }; $d.Rows.Add($row) }
            $grid.DataSource = $d; foreach ($c in $grid.Columns) { $c.Width = 110 }; $grid.Columns['Scenario'].Width = 170; $grid.Columns['What happened'].Width = 300; $grid.Columns['Where'].Width = 130; $grid.Columns['Details'].Width = 520; $grid.Columns['Time'].Width = 150
            $lv = @($all | Group-Object Severity | Sort-Object { $global:HaySevRank[$_.Name] } -Descending | ForEach-Object { "$($_.Name) $($_.Count)" })
            $sum.Text = if ($all.Count) { "$($all.Count) findings: $($lv -join ', ')" } else { 'No matching events in these logs.' }
            $none = @($perScen | Where-Object { $_.Status -eq 'OK' -and $_.Count -eq 0 -and $_.Cmd -eq 'dfir-timeline' } | ForEach-Object { $_.Title }); $failed = @($perScen | Where-Object { $_.Status -notin 'OK' } | ForEach-Object { "$($_.Title) ($($_.Status))" })
            $sum2.Text = $(if ($none.Count) { 'Nothing found for: ' + ($none -join '; ') + '. ' } else { '' }) + $(if ($failed.Count) { 'Did not complete: ' + ($failed -join '; ') + '. ' } else { '' }) + 'Findings are rule matches for review, not proof of compromise. Reports (counts, logon summary, event IDs) are in the results folder.'
            $bhtml.Enabled = [bool]$state.Report; & $apply } 'Hayabusa' }.GetNewClosure())
    $p }
function Build-HayabusaAdvancedPage {
    $p = NPanel; foreach ($c in (NHeading 'Hayabusa Advanced' 'Every command, option and filter of the bundled Hayabusa, read from its own help. For ready-made investigations use the Hayabusa page.')) { $p.Controls.Add($c) }
    $st = NLabel '' 20 80 1000 20 $global:C.Dim; $p.Controls.Add($st)
    $hi = Get-HayabusaInfo
    if (-not $hi.Present) { $st.Text = 'Hayabusa was not found in tools\Hayabusa.'; $st.ForeColor = $global:C.Bad; return $p }
    if (-not $hi.Runnable) { $st.Text = "Hayabusa cannot run: $($hi.BlockReason)"; $st.ForeColor = $global:C.Bad; return $p }
    $st.Text = "$($hi.Version). $($hi.RuleFiles) rule files."; $st.ForeColor = $global:C.Ok
    $presets = @(Get-HayabusaPresets); $cmds = @($global:HayCommands.Keys)
    $p.Controls.Add((NLabel 'Preset' 20 108 120)); $pc = NCombo 20 128 360; foreach ($x in $presets) { [void]$pc.Items.Add($x.Name) }; $p.Controls.Add($pc)
    $bap = NButton 'Apply preset' 390 126 110 28; $p.Controls.Add($bap)
    $p.Controls.Add((NLabel 'Command' 520 108 120)); $cc = NCombo 520 128 300; foreach ($c in $cmds) { [void]$cc.Items.Add($c) }; $cc.SelectedIndex = 0; $p.Controls.Add($cc)
    $cd = NLabel '' 830 132 230 36 $global:C.Dim (F 8.5); $p.Controls.Add($cd)
    $p.Controls.Add((NLabel 'Input' 20 162 100)); $ik = NCombo 20 182 140; [void]$ik.Items.AddRange(@('Folder', 'File', 'Live system')); $ik.SelectedIndex = 0; $p.Controls.Add($ik)
    $ip = NText 170 183 560 $(if ($global:Case) { Join-Path $global:Case.Dir '05_Event_Logs\raw_evtx' } else { '' }); $p.Controls.Add($ip)
    $bb = NButton 'Browse...' 740 181 90 26; $p.Controls.Add($bb)
    $bb.Add_Click({ if ($ik.SelectedItem -eq 'File') { $d = New-Object Windows.Forms.OpenFileDialog; $d.Filter = 'Event logs|*.evtx;*.csv;*.json;*.jsonl|All|*.*'; if ($d.ShowDialog() -eq 'OK') { $ip.Text = $d.FileName } } else { $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $ip.Text = $d.SelectedPath } } }.GetNewClosure())
    $ik.Add_SelectedIndexChanged({ $ip.Enabled = ($ik.SelectedItem -ne 'Live system'); $bb.Enabled = $ip.Enabled }.GetNewClosure())
    $op = New-Object Windows.Forms.Panel; $op.Location = New-Object Drawing.Point(20, 218); $op.Size = New-Object Drawing.Size(1000, 260); $op.AutoScroll = $true; $op.BackColor = $global:C.Panel; $op.Anchor = 'Top,Left,Right'; $p.Controls.Add($op)
    $ctl = @{}; $profiles = @(Get-HayabusaProfiles)
    $fill = {
        $op.Controls.Clear(); $ctl.Clear(); $spec = Get-HayabusaSpec ([string]$cc.SelectedItem); $cd.Text = $global:HayCommands[[string]$cc.SelectedItem]
        $y = 8
        foreach ($sec in $spec.Sections) {
            $opts = @($sec.Options | Where-Object { $global:HayHidden -notcontains $_.Long -or $_.Long -eq '--html-report' })
            if ($sec.Name -eq 'Time Format') {
                $op.Controls.Add((NLabel 'TIME FORMAT' 10 $y 300 18 $global:C.Accent (F 8 'Bold'))); $y += 22
                $op.Controls.Add((NLabel 'Timestamp format' 10 ($y + 3) 300)); $tc = NCombo 320 $y 420; [void]$tc.Items.Add(''); foreach ($o in $opts) { [void]$tc.Items.Add($o.Long); $global:G.Tip.SetToolTip($tc, 'Choose how timestamps are written. --utc is recommended for evidence.') }
                $tc.SelectedItem = '--utc'; $op.Controls.Add($tc); $ctl['@time'] = $tc; $y += 34; continue }
            if (-not $opts.Count) { continue }
            $op.Controls.Add((NLabel $sec.Name.ToUpper() 10 $y 400 18 $global:C.Accent (F 8 'Bold'))); $y += 22
            $flags = @($opts | Where-Object { -not $_.Value }); $vals = @($opts | Where-Object { $_.Value })
            $col = 0
            foreach ($o in $flags) {
                $lbl = $o.Long; if ($o.Short) { $lbl = "$($o.Short), $($o.Long)" }; if ($o.Long -eq '--html-report') { $lbl = '--html-report (save an HTML summary)' }
                $cb = NCheck $lbl (10 + 320 * $col) $y 316 $o.Desc; $op.Controls.Add($cb); $ctl[$o.Long.Substring(2)] = $cb
                $col++; if ($col -ge 3) { $col = 0; $y += 24 } }
            if ($col -ne 0) { $y += 24 }
            foreach ($o in $vals) {
                $lbl = $o.Long; if ($o.Short) { $lbl = "$($o.Short), $($o.Long)" }
                $op.Controls.Add((NLabel "$lbl  <$($o.Value)>" 10 ($y + 3) 300 20 $global:C.Text (F 8.5)))
                if ($global:HayEnums.ContainsKey($o.Long)) { $c = NCombo 320 $y 200; [void]$c.Items.Add(''); foreach ($x in $global:HayEnums[$o.Long]) { [void]$c.Items.Add($x) } }
                elseif ($o.Long -eq '--profile') { $c = NCombo 320 $y 200; [void]$c.Items.Add(''); foreach ($x in $profiles) { [void]$c.Items.Add($x) } }
                else { $c = NText 320 $y 420 }
                $global:G.Tip.SetToolTip($c, $o.Desc); $op.Controls.Add($c); $ctl[$o.Long.Substring(2)] = $c
                $op.Controls.Add((NLabel $o.Desc 750 ($y + 4) 400 18 $global:C.Dim (F 8)))
                $y += 30 }
            $y += 8
        }
    }.GetNewClosure()
    $getVals = {
        $o = @{}
        foreach ($k in $ctl.Keys) { $c = $ctl[$k]
            if ($k -eq '@time') { if ($c.SelectedItem) { $o[([string]$c.SelectedItem).Substring(2)] = $true }; continue }
            if ($c -is [Windows.Forms.CheckBox]) { if ($c.Checked) { $o[$k] = $true } }
            elseif ($c -is [Windows.Forms.ComboBox]) { if ($c.SelectedItem -and [string]$c.SelectedItem) { $o[$k] = [string]$c.SelectedItem } }
            else { if ($c.Text.Trim()) { $o[$k] = $c.Text.Trim() } } }
        $o }.GetNewClosure()
    $getIn = { switch ($ik.SelectedItem) { 'Folder' { @{ Kind = 'directory'; Path = $ip.Text.Trim() } } 'File' { @{ Kind = 'file'; Path = $ip.Text.Trim() } } default { @{ Kind = 'live'; Path = '' } } } }.GetNewClosure()
    $noInput = @('sort-csv', 'config-critical-systems') ; $cc.Add_SelectedIndexChanged($fill); & $fill
    $bap.Add_Click({ if ($pc.SelectedIndex -lt 0) { return }; $pr = $presets[$pc.SelectedIndex]; $cc.SelectedItem = [string]$pr.Command; & $fill
        foreach ($pp in $pr.Options.PSObject.Properties) { $k = $pp.Name; $v = $pp.Value
            if ($ctl.ContainsKey('@time') -and $k -in 'utc', 'iso-8601', 'european-time', 'rfc-2822', 'rfc-3339', 'us-time', 'us-military-time') { if ($v) { $ctl['@time'].SelectedItem = "--$k" }; continue }
            if (-not $ctl.ContainsKey($k)) { continue }; $c = $ctl[$k]
            if ($c -is [Windows.Forms.CheckBox]) { $c.Checked = [bool]$v } elseif ($c -is [Windows.Forms.ComboBox]) { $c.SelectedItem = [string]$v } else { $c.Text = [string]$v } }
        Gui-Log INFO "Preset applied: $($pr.Name)" }.GetNewClosure())
    $br = NButton 'Run' 20 488 130 34 $true 'Runs Hayabusa with the options above. Output goes to 11_Hayabusa_Analysis in the case folder.'; $bv = NButton 'Show command' 160 488 140 34 $false 'Shows the exact command line that will be run.'; $bh = NButton 'Show help' 310 488 120 34 $false 'The help text of this command from the installed Hayabusa.'
    $bo = NButton 'Open results folder' 440 488 160 34; $p.Controls.AddRange(@($br, $bv, $bh, $bo))
    $grid = NGrid 20 532 1000 120; $grid.Anchor = 'Top,Left,Right'; $p.Controls.Add($grid)
    $show = { param($path) try { $rows = @(Import-HayabusaResults $path 2000); $dt = New-Object Data.DataTable; if ($rows.Count) { foreach ($c in $rows[0].PSObject.Properties.Name) { [void]$dt.Columns.Add($c) }; foreach ($x in $rows) { $row = $dt.NewRow(); foreach ($c in $dt.Columns) { $row[$c.ColumnName] = [string]$x.($c.ColumnName) }; $dt.Rows.Add($row) } }; $grid.DataSource = $dt; Gui-Log INFO "Loaded $($rows.Count) rows (first 2000 shown)" } catch { Gui-Log WARN "Could not load results: $($_.Exception.Message)" } }.GetNewClosure()
    $br.Add_Click({ $cmd = [string]$cc.SelectedItem; $in = & $getIn; if ($cmd -in $noInput -and $in.Kind -eq 'live') { Gui-Msg "$cmd needs a folder or file."; return }
        $opts = & $getVals; if (Gui-Confirm "Run Hayabusa $cmd on $(if ($in.Kind -eq 'live') { 'the live event logs of this system' } else { $in.Path })?") {
            Gui-Run { $r = Invoke-Hayabusa -Command $cmd -InSpec $in -Options $opts; Gui-ShowResults @($r); $f = @($r.Destination | Where-Object { $_ -match '\.(csv|jsonl?)$' -and $_ -notmatch 'raw_|help_' } | Select-Object -First 1); if ($f.Count) { & $show (Join-Path $global:Case.Dir $f[0]) } } "Hayabusa $cmd" } }.GetNewClosure())
    $bv.Add_Click({ try { $in = & $getIn; $b = Build-HayabusaArgs -Command ([string]$cc.SelectedItem) -InSpec $in -Options (& $getVals) -OutDir '<case>\11_Hayabusa_Analysis\<run>'; Gui-Msg ((Get-HayabusaInfo).Path + "`r`n" + (ConvertTo-ArgString $b.Args) + $(if ($b.Notes.Count) { "`r`n`r`n" + ($b.Notes -join "`r`n") } else { '' })) 'Command line' } catch { Gui-Msg $_.Exception.Message 'Cannot build command' 'Warning' } }.GetNewClosure())
    $bh.Add_Click({ $f = New-Object Windows.Forms.Form; $f.Text = "Hayabusa help: $($cc.SelectedItem)"; $f.Size = New-Object Drawing.Size(1000, 760); $t = NText 0 0 980 ((Get-HayabusaSpec ([string]$cc.SelectedItem)).Help) $true; $t.Dock = 'Fill'; $t.ReadOnly = $true; $t.Font = New-Object Drawing.Font('Consolas', 9); $f.Controls.Add($t); [void]$f.ShowDialog() }.GetNewClosure())
    $bo.Add_Click({ if ($global:Case) { Start-Process explorer.exe -ArgumentList (ConvertTo-ArgString @((Get-CaseFolder 'Hay'))) } })
    $p }
function Build-ChainsawPage {
    $p = NPanel; foreach ($c in (NHeading 'Chainsaw' 'Runs the bundled Chainsaw. Options are only passed if the installed version lists them in its own help. A rule match is a lead for review, not a confirmed compromise.')) { $p.Controls.Add($c) }
    $st = NLabel '' 20 84 1000 22 $global:C.Dim; $p.Controls.Add($st)
    $rf = { $global:ChainsawCache = $null; $ci = Get-ChainsawInfo -Refresh
        if (-not $ci.Present) { $st.Text = 'Chainsaw was not found in tools\Chainsaw.'; $st.ForeColor = $global:C.Bad }
        elseif (-not $ci.Runnable) { $st.Text = "Chainsaw cannot run: $($ci.BlockReason)"; $st.ForeColor = $global:C.Bad }
        else { $st.Text = "Ready. $($ci.Version)"; $st.ForeColor = $global:C.Ok } }.GetNewClosure()
    & $rf
    $bh = NButton 'Show help output' 20 114 150 30 $false 'Runs chainsaw --help, hunt --help and search --help.'; $p.Controls.Add($bh)
    $brf = NButton 'Check again' 180 114 110 30; $p.Controls.Add($brf); $brf.Add_Click($rf)
    $p.Controls.Add((NLabel 'EVTX file or folder' 20 160 200)); $inp = NText 20 182 560 $(if ($global:Case) { Join-Path $global:Case.Dir '05_Event_Logs\raw_evtx' } else { '' }); $p.Controls.Add($inp)
    $b1 = NButton 'Folder...' 590 180 80 26; $b2 = NButton 'File...' 676 180 80 26; $p.Controls.AddRange(@($b1, $b2))
    $b1.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $inp.Text = $d.SelectedPath } }.GetNewClosure())
    $b2.Add_Click({ $d = New-Object Windows.Forms.OpenFileDialog; $d.Filter = 'EVTX|*.evtx|All|*.*'; if ($d.ShowDialog() -eq 'OK') { $inp.Text = $d.FileName } }.GetNewClosure())
    $p.Controls.Add((NLabel 'Detection profile' 20 218 200)); $pc = NCombo 20 240 560
    $profs = @(Get-ChainsawProfiles); foreach ($x in $profs) { [void]$pc.Items.Add("$($x.Name) - $($x.Description)") }; if ($pc.Items.Count) { $pc.SelectedIndex = 0 }; $p.Controls.Add($pc)
    $p.Controls.Add((NLabel 'Output format' 600 218 120)); $fc = NCombo 600 240 120; [void]$fc.Items.AddRange(@('csv', 'json', 'table', 'log')); $fc.SelectedIndex = 0; $p.Controls.Add($fc)
    $p.Controls.Add((NLabel 'From (optional)' 20 276 150)); $fr = NText 20 298 180; $p.Controls.Add($fr); $p.Controls.Add((NLabel 'To (optional)' 212 276 150)); $to = NText 212 298 180; $p.Controls.Add($to)
    $bhunt = NButton 'Run hunt' 410 296 140 30 $true 'chainsaw hunt with the selected profile. Output and exact arguments are saved in 11_Chainsaw_Analysis.'; $p.Controls.Add($bhunt)
    $p.Controls.Add((NLabel 'Search pattern (regex)' 20 336 200)); $pat = NText 20 358 400; $p.Controls.Add($pat)
    $bs = NButton 'Run search' 430 356 120 30; $p.Controls.Add($bs)
    $p.Controls.Add((NLabel 'Open results (CSV/JSON file or folder)' 20 400 400)); $rp = NText 20 422 560; $p.Controls.Add($rp)
    $b3 = NButton 'Browse...' 590 420 90 26; $bl = NButton 'Load' 686 420 80 26 $true; $p.Controls.AddRange(@($b3, $bl))
    $b3.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $rp.Text = $d.SelectedPath } }.GetNewClosure())
    $grid = NGrid 20 458 980 150; $grid.Anchor = 'Top,Left,Right,Bottom'; $p.Controls.Add($grid)
    $bl.Add_Click({ try { $r = @(Import-ChainsawResults $rp.Text); $dt = New-Object Data.DataTable; if ($r.Count) { foreach ($c in $r[0].PSObject.Properties.Name) { [void]$dt.Columns.Add($c) }; foreach ($x in ($r | Select-Object -First 2000)) { $row = $dt.NewRow(); foreach ($c in $dt.Columns) { $row[$c.ColumnName] = [string]$x.($c.ColumnName) }; $dt.Rows.Add($row) } }; $grid.DataSource = $dt; Gui-Log INFO "Loaded $($r.Count) rows (first 2000 shown)" } catch { Gui-Msg $_.Exception.Message 'Cannot load results' 'Warning' } }.GetNewClosure())
    $bh.Add_Click({ $ci = Get-ChainsawInfo; if (-not $ci.Runnable) { Gui-Msg "Chainsaw cannot run here, so there is no help output.`r`n$($ci.BlockReason)" 'Chainsaw' 'Warning'; return }
        $f = New-Object Windows.Forms.Form; $f.Text = 'Chainsaw help'; $f.Size = New-Object Drawing.Size(900, 700); $t = NText 0 0 880 ($ci.Help.GetEnumerator() | ForEach-Object { "=== $($_.Key) ===`r`n$($_.Value)" } | Out-String) $true; $t.Dock = 'Fill'; $t.ReadOnly = $true; $t.Font = New-Object Drawing.Font('Consolas', 9); $f.Controls.Add($t); [void]$f.ShowDialog() }.GetNewClosure())
    $bhunt.Add_Click({ if ($pc.SelectedIndex -lt 0) { return }; $pr = $profs[$pc.SelectedIndex]; $ci = Get-ChainsawInfo
        $O = @{ Input = @($inp.Text); Format = [string]$fc.SelectedItem; Sigma = (Resolve-ChainsawRel $ci.Dir $pr.Sigma); Rules = (Resolve-ChainsawRel $ci.Dir $pr.Rules); Mapping = (Resolve-ChainsawRel $ci.Dir $pr.Mapping); Level = @($pr.Level); SkipErrors = $true; From = $fr.Text; To = $to.Text }
        if (Gui-Confirm "Run hunt with '$($pr.Name)' on:`r`n$($inp.Text)") { Gui-Run { $r = Invoke-Chainsaw -Sub hunt -O $O; Gui-ShowResults @($r) } 'Chainsaw hunt' } }.GetNewClosure())
    $bs.Add_Click({ if (-not $pat.Text) { Gui-Msg 'Enter a search pattern.'; return }; $O = @{ Input = @($inp.Text); Pattern = $pat.Text; Format = 'json'; IgnoreCase = $true; SkipErrors = $true }
        Gui-Run { $r = Invoke-Chainsaw -Sub search -O $O; Gui-ShowResults @($r) } 'Chainsaw search' }.GetNewClosure())
    $p }

function Build-KapePage {
    $p = NPanel; foreach ($c in (NHeading 'KAPE' 'Targets collect artifacts from a live system or mounted image. Modules process data that was already collected. Only targets and modules found in your KAPE folder are listed.')) { $p.Controls.Add($c) }
    $k = Get-KapeInfo
    if (-not $k.Present) { $p.Controls.Add((NLabel 'KAPE is not in tools\KAPE. It is distributed by Kroll after a registration form and cannot be bundled by AS4. Copy kape.exe with its Targets and Modules folders into tools\KAPE, then restart the tool. See tools\README.md.' 20 90 960 60 $global:C.Warn)); return $p }
    $p.Controls.Add((NLabel "KAPE $($k.Version): $($k.Targets.Count) targets, $($k.Modules.Count) modules" 20 84 600 20 $global:C.Ok))
    $p.Controls.Add((NLabel 'Targets' 20 112 200)); $p.Controls.Add((NLabel 'Modules' 360 112 300))
    $tl = NCheckList 20 134 330 400; foreach ($t in $k.Targets) { [void]$tl.Items.Add($t.Name) }; $p.Controls.Add($tl)
    $ml = NCheckList 360 134 330 400; foreach ($m in $k.Modules) { [void]$ml.Items.Add($m.Name) }; $p.Controls.Add($ml)
    $pc = NCombo 710 134 320; $profs = @(Get-KapeProfiles); foreach ($x in $profs) { [void]$pc.Items.Add($x.Name) }; $p.Controls.Add($pc)
    $p.Controls.Add((NLabel 'Scenario profile' 710 112 200)); $pd = NLabel '' 710 166 320 80 $global:C.Dim; $p.Controls.Add($pd)
    $pc.Add_SelectedIndexChanged({ $x = $profs[$pc.SelectedIndex]; $pd.Text = "$($x.Description)`r`nNot found in this KAPE: $($x.MissingTargets -join ', ')"
        for ($i = 0; $i -lt $tl.Items.Count; $i++) { $tl.SetItemChecked($i, ($x.Targets -contains $tl.Items[$i])) } }.GetNewClosure())
    $p.Controls.Add((NLabel 'Source (drive or mounted image)' 710 252 320)); $src = NText 710 274 320 'C:'; $p.Controls.Add($src)
    $br = NButton 'Run KAPE' 710 312 320 34 $true 'Live collection reads from the source and needs administrator.'; $p.Controls.Add($br)
    $br.Add_Click({ $tg = @($tl.CheckedItems | ForEach-Object { [string]$_ }); $md = @($ml.CheckedItems | ForEach-Object { [string]$_ })
        if (-not $tg.Count -and -not $md.Count) { Gui-Msg 'Select targets and/or modules.'; return }
        if (Gui-Confirm "Run KAPE on '$($src.Text)'`r`nTargets: $($tg -join ', ')`r`nModules: $($md -join ', ')`r`nOutput: $($global:Case.Dir)\06_KAPE" 'Run KAPE' $true) { Gui-Run { Gui-ShowResults @(Invoke-Kape -Source $src.Text -Targets $tg -Modules $md) } 'KAPE' } }.GetNewClosure())
    $p }

function Build-MemoryPage {
    $p = NPanel; foreach ($c in (NHeading 'Memory' 'Memory capture changes the running system and the image can hold credentials and personal data. It is saved only inside the case folder (or the folder you choose).')) { $p.Controls.Add($c) }
    $p.Controls.Add((NSection 'Capture with FTK Imager' 20 90))
    $p.Controls.Add((NLabel "1. Press Open FTK Imager (the case folder path is copied to the clipboard).`r`n2. In FTK Imager: File > Capture Memory. Paste the destination path, set a file name, then Capture Memory.`r`n3. When it finishes, press Register output so the dump is hashed (SHA-256) and recorded." 20 112 960 60 $global:C.Dim))
    $bf = NButton 'Open FTK Imager' 20 180 170 34 $true 'Starts the bundled FTK Imager. Needs administrator for memory capture.'; $p.Controls.Add($bf)
    $br = NButton 'Register output' 200 180 150 34 $false 'Hashes and records the files FTK Imager wrote to the memory folder.'; $p.Controls.Add($br)
    $bf.Add_Click({ Gui-Run { Gui-ShowResults @(Start-FtkImager -Mode memory) } 'Opening FTK Imager' }.GetNewClosure())
    $br.Add_Click({ Gui-Run { Gui-ShowResults @(Register-FtkOutput -Mode memory) } 'Recording FTK output' }.GetNewClosure())
    $p.Controls.Add((NSection 'Capture with WinPmem' 20 242))
    $p.Controls.Add((NLabel 'Destination folder' 20 266 300)); $dest = NText 20 288 560 $(if ($global:Case) { Join-Path $global:Case.Dir '07_Memory' } else { '' }); $p.Controls.Add($dest)
    $bb = NButton 'Browse...' 590 286 90 26; $p.Controls.Add($bb); $bb.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $dest.Text = $d.SelectedPath } }.GetNewClosure())
    $sp = NLabel '' 20 318 900 20 $global:C.Dim; $p.Controls.Add($sp)
    $bc = NButton 'Check free space' 20 342 150 30; $p.Controls.Add($bc)
    $bc.Add_Click({ if (-not (Test-Path -LiteralPath $dest.Text)) { New-Item -ItemType Directory -Path $dest.Text -Force | Out-Null }; $s = Test-MemorySpace $dest.Text; $sp.Text = ("RAM {0} GB, free at destination {1} GB: {2}" -f [math]::Round($s.RamBytes / 1GB, 1), [math]::Round($s.FreeBytes / 1GB, 1), $(if ($s.Sufficient) { 'enough space' } else { 'NOT ENOUGH SPACE' })); $sp.ForeColor = $(if ($s.Sufficient) { $global:C.Ok } else { $global:C.Bad }) }.GetNewClosure())
    $p.Controls.Add((NLabel 'WinPmem arguments ({OUT} is replaced by the output file; check the tool help)' 20 382 700)); $wargs = NText 20 404 560 '{OUT}'; $p.Controls.Add($wargs)
    $bhp = NButton 'Show help' 590 402 100 28; $p.Controls.Add($bhp)
    $bhp.Add_Click({ Gui-Run { $t = Get-As4Tool 'winpmem'; Gui-Msg (Get-MemToolHelp $t) 'WinPmem help' } 'Reading help' }.GetNewClosure())
    $ba = NButton 'Capture with WinPmem' 20 440 200 34 $true 'Needs administrator. Checks space first and hashes the image afterwards.'; $p.Controls.Add($ba)
    $ba.Add_Click({ if (Gui-Confirm "Capture physical memory with WinPmem into:`r`n$($dest.Text)`r`n`r`nThis changes the running system and the dump may contain credentials. Continue?" 'Memory capture' $true) { Gui-Run { Gui-ShowResults @(Invoke-MemoryAcquisition -ToolId winpmem -DestDir $dest.Text -ArgTemplate $wargs.Text) } 'Capturing memory' } }.GetNewClosure())
    $p.Controls.Add((NSection 'Analyse an existing dump (Volatility 3)' 20 494))
    $dump = NText 20 518 560; $p.Controls.Add($dump)
    $bd = NButton 'Browse...' 590 516 90 26; $p.Controls.Add($bd); $bd.Add_Click({ $d = New-Object Windows.Forms.OpenFileDialog; if ($d.ShowDialog() -eq 'OK') { $dump.Text = $d.FileName } }.GetNewClosure())
    $pl = NText 20 552 220 'windows.info'; $p.Controls.Add($pl); $bv = NButton 'Run plugin' 250 550 110 28; $p.Controls.Add($bv)
    $bv.Add_Click({ Gui-Run { Gui-ShowResults @(Invoke-Volatility -Dump $dump.Text -Plugin $pl.Text) } 'Volatility' }.GetNewClosure())
    $p }

function Build-DiskImagePage {
    $p = NPanel; foreach ($c in (NHeading 'Disk Image' 'Create a forensic disk image with FTK Imager. The image is written inside the case folder (08_Disk).')) { $p.Controls.Add($c) }
    $p.Controls.Add((NSection 'FTK Imager (graphical)' 20 90))
    $p.Controls.Add((NLabel "1. Press Open FTK Imager (the case folder path is copied to the clipboard).`r`n2. In FTK Imager: File > Create Disk Image, choose the source drive, then add a destination (E01 or raw) and paste the path.`r`n3. When it finishes, press Register output so the image and FTK's hash report are hashed and recorded." 20 112 960 60 $global:C.Dim))
    $bf = NButton 'Open FTK Imager' 20 180 170 34 $true 'Starts the bundled FTK Imager.'; $br = NButton 'Register output' 200 180 150 34; $p.Controls.AddRange(@($bf, $br))
    $bf.Add_Click({ Gui-Run { Gui-ShowResults @(Start-FtkImager -Mode disk) } 'Opening FTK Imager' }.GetNewClosure())
    $br.Add_Click({ Gui-Run { Gui-ShowResults @(Register-FtkOutput -Mode disk) } 'Recording FTK output' }.GetNewClosure())
    $p.Controls.Add((NSection 'FTK Imager command line' 20 242))
    $p.Controls.Add((NLabel 'Source, for example \\.\PHYSICALDRIVE1' 20 266 400)); $src = NText 20 288 400; $p.Controls.Add($src)
    $p.Controls.Add((NLabel 'Image name' 440 266 200)); $nm = NText 440 288 220 'disk_image'; $p.Controls.Add($nm)
    $vf = NCheck 'Verify after imaging' 680 288 200; $p.Controls.Add($vf)
    $bc = NButton 'Create image' 20 326 150 34 $true 'Needs ftkimager.exe (CLI) in tools\DiskForensics and administrator rights.'; $p.Controls.Add($bc)
    $bc.Add_Click({ if (Gui-Confirm "Image '$($src.Text)' into the case folder?" 'Disk image' $true) { Gui-Run { Gui-ShowResults @(Invoke-FtkCliImage -Source $src.Text -Name $nm.Text -Verify:$vf.Checked) } 'Imaging disk' } }.GetNewClosure())
    $p }

function Build-ArtifactPage {
    $p = NPanel; foreach ($c in (NHeading 'Artifacts' 'Select what to collect. Raw $MFT, $LogFile and $J need raw disk access and are not copied here; use KAPE or FTK Imager for those.')) { $p.Controls.Add($c) }
    $cat = @(Get-As4ArtifactCatalog); $cl = NCheckList 20 90 470 420; foreach ($c in $cat) { [void]$cl.Items.Add($c.Name) }; $p.Controls.Add($cl)
    $dt = NText 504 90 500 '' $true 230; $dt.ReadOnly = $true; $p.Controls.Add($dt)
    $cl.Add_SelectedIndexChanged({ if ($cl.SelectedIndex -ge 0) { $c = $cat[$cl.SelectedIndex]; $dt.Text = "$($c.Name)`r`n`r`nCollects: $($c.What)`r`nWhy: $($c.Why)`r`nForensic value: $($c.Value)`r`nAdministrator: $($c.Admin)`r`nSensitive data: $($c.Sensitive)`r`nLive collection: $($c.Live)`r`n$($c.Note)" } }.GetNewClosure())
    $p.Controls.Add((NLabel 'Changed in last N days' 504 332 160)); $dy = NText 504 354 90; $p.Controls.Add($dy)
    $p.Controls.Add((NLabel 'Extensions (exe,dll)' 610 332 160)); $ex = NText 610 354 150; $p.Controls.Add($ex)
    $p.Controls.Add((NLabel 'Max file MB' 776 332 100)); $mb = NText 776 354 80 '0'; $p.Controls.Add($mb)
    $du = NCheck 'Report duplicate SHA-256' 504 386 220; $p.Controls.Add($du); $du.Checked = $true
    $bc = NButton 'Collect selected' 504 418 160 34 $true; $p.Controls.Add($bc)
    $bcu = NButton 'Collect a folder...' 674 418 170 34 $false 'Copies files from a folder you choose. The filters above apply. The source is only read.'; $p.Controls.Add($bcu)
    $filters = { @{ Since = $(if ($dy.Text) { (Get-Date).AddDays(-[int]$dy.Text) }); Ext = @($ex.Text -split ',' | ForEach-Object { $_.Trim().TrimStart('.').ToLower() } | Where-Object { $_ }); Mb = [double]$mb.Text } }.GetNewClosure()
    $bc.Add_Click({ $ids = @(); for ($i = 0; $i -lt $cl.Items.Count; $i++) { if ($cl.GetItemChecked($i)) { $ids += $cat[$i].Id } }
        if (-not $ids.Count) { Gui-Msg 'Select at least one category.'; return }
        $sens = @($cat | Where-Object { $ids -contains $_.Id -and $_.Sensitive } | ForEach-Object { $_.Name })
        if (Gui-Confirm ("Collect {0} categories into the case?{1}" -f $ids.Count, $(if ($sens) { "`r`nThese may contain sensitive data:`r`n - " + ($sens -join "`r`n - ") + "`r`nMake sure you are authorised." } else { '' })) 'Collect artifacts' ([bool]$sens)) {
            $f = & $filters; Gui-Run { Gui-ShowResults (Invoke-As4Artifacts -Ids $ids -Since $f.Since -Extensions $f.Ext -MaxMB $f.Mb -Duplicates:$du.Checked -OnProgress { param($i, $n, $c) Gui-Progress $i $n $c.Name }) } 'Collecting artifacts' } }.GetNewClosure())
    $bcu.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $f = & $filters; $fp = $d.SelectedPath; if (Gui-Confirm "Copy matching files from $fp into the case?") { Gui-Run { Gui-ShowResults @(Invoke-As4FolderCollection -Folders @($fp) -Since $f.Since -Extensions $f.Ext -MaxMB $f.Mb -Duplicates:$du.Checked) } 'Collecting folder' } } }.GetNewClosure())
    $p }

function Build-AnalysisPage {
    $p = NPanel; foreach ($c in (NHeading 'IOC, YARA and Timeline' 'Offline analysis of collected data. Matches are leads for review. No network lookups are made.')) { $p.Controls.Add($c) }
    $p.Controls.Add((NSection 'IOC search' 20 90))
    $p.Controls.Add((NLabel 'IOC list (one per line: hash, IP, domain, URL or path)' 20 114 500)); $iocf = NText 20 136 560; $p.Controls.Add($iocf); $b = NButton 'Browse...' 590 134 90 26; $p.Controls.Add($b)
    $b.Add_Click({ $d = New-Object Windows.Forms.OpenFileDialog; $d.InitialDirectory = $global:P.Rules; if ($d.ShowDialog() -eq 'OK') { $iocf.Text = $d.FileName } }.GetNewClosure())
    $p.Controls.Add((NLabel 'Search in (default: the whole case)' 20 170 300)); $root = NText 20 192 560 $(if ($global:Case) { $global:Case.Dir } else { '' }); $p.Controls.Add($root)
    $bi = NButton 'Search' 590 190 100 28 $true; $p.Controls.Add($bi)
    $bi.Add_Click({ Gui-Run { $r = Invoke-As4IocSearch -IocFile $iocf.Text -SearchRoot $root.Text; Gui-Log OK "IOC search: $($r.Hits) hits, $($r.Scanned) files scanned, $($r.Skipped) skipped. $($r.HitsFile)" } 'IOC search' }.GetNewClosure())
    $p.Controls.Add((NSection 'YARA' 20 240))
    $p.Controls.Add((NLabel 'Rules file' 20 264 300)); $yr = NText 20 286 560; $p.Controls.Add($yr); $by = NButton 'Browse...' 590 284 90 26; $p.Controls.Add($by)
    $by.Add_Click({ $d = New-Object Windows.Forms.OpenFileDialog; $d.InitialDirectory = $global:P.Rules; if ($d.ShowDialog() -eq 'OK') { $yr.Text = $d.FileName } }.GetNewClosure())
    $p.Controls.Add((NLabel 'File or folder to scan' 20 320 400)); $yt = NText 20 342 560; $p.Controls.Add($yt); $by2 = NButton 'Folder...' 590 340 90 26; $p.Controls.Add($by2)
    $by2.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $yt.Text = $d.SelectedPath } }.GetNewClosure())
    $bs = NButton 'Scan' 690 340 100 28 $true; $p.Controls.Add($bs); $bs.Add_Click({ Gui-Run { Gui-ShowResults @(Invoke-Yara -Rules $yr.Text -Target $yt.Text) } 'YARA' }.GetNewClosure())
    $p.Controls.Add((NSection 'Timeline' 20 396))
    $p.Controls.Add((NLabel 'Builds a UTC timeline CSV from timestamps in the collected CSV files. Rows without a time zone are marked as uncertain.' 20 420 900 20 $global:C.Dim))
    $bt = NButton 'Build timeline' 20 448 160 32 $true; $p.Controls.Add($bt)
    $bt.Add_Click({ Gui-Run { $r = Invoke-As4Timeline; Gui-Log OK "Timeline: $($r.Rows) rows. $($r.File)" } 'Building timeline' })
    $p }

function Build-ReportPage {
    $p = NPanel; foreach ($c in (NHeading 'Report and Integrity' 'Verify the SHA-256 hash ledger of this case and produce the report (HTML, CSV and JSON).')) { $p.Controls.Add($c) }
    $bv = NButton 'Verify hashes' 20 90 160 34 $true; $br = NButton 'Create report' 190 90 160 34 $true; $bo = NButton 'Open case folder' 360 90 160 34
    $p.Controls.AddRange(@($bv, $br, $bo))
    $grid = NGrid 20 140 980 440; $grid.Anchor = 'Top,Left,Right,Bottom'; $p.Controls.Add($grid)
    $bv.Add_Click({ Gui-Run { $v = Invoke-As4Verify $global:Case.Id; Gui-Log $(if ($v.Problems) { 'ERROR' } else { 'OK' }) "Checked $($v.Total) files: $($v.OK) OK, $($v.Problems) problems"; $dt = New-Object Data.DataTable; foreach ($c in 'Status', 'RelativePath', 'Expected', 'Actual') { [void]$dt.Columns.Add($c) }; foreach ($d in $v.Details) { [void]$dt.Rows.Add($d.Status, $d.RelativePath, $d.Expected, $d.Actual) }; $grid.DataSource = $dt; Gui-Msg "Checked $($v.Total) files.`r`nOK: $($v.OK)`r`nProblems: $($v.Problems)" 'Hash verification' $(if ($v.Problems) { 'Warning' } else { 'Information' }) } 'Verifying hashes' }.GetNewClosure())
    $br.Add_Click({ Gui-Run { $r = New-As4Report $global:Case.Id; Gui-Log OK "Report: $($r.Html)"; Start-Process $r.Html } 'Creating report' })
    $bo.Add_Click({ if ($global:Case) { Start-Process explorer.exe -ArgumentList (ConvertTo-ArgString @($global:Case.Dir)) } })
    $p }

function Update-ToolsGrid {
    $g = $global:G.ToolsGrid; $dt = New-Object Data.DataTable; foreach ($c in 'Tool', 'Status', 'Version', 'License', 'Path') { [void]$dt.Columns.Add($c) }
    foreach ($t in Get-As4Tools) { [void]$dt.Rows.Add($t.Name, $t.Status, $t.FileVersion, $t.License, $t.Path) }; $g.DataSource = $dt }
function Build-ToolsPage {
    $p = NPanel; foreach ($c in (NHeading 'Tools' 'Everything under the tools folder. PRESENT_UNVERIFIED means the file exists but its hash is not in config\tools_manifest.json. Missing tools are never downloaded by AS4.')) { $p.Controls.Add($c) }
    $g = NGrid 20 130 980 440; $g.Anchor = 'Top,Left,Right,Bottom'; $g.SelectionMode = 'FullRowSelect'; $g.MultiSelect = $false; $p.Controls.Add($g); $global:G.ToolsGrid = $g
    $bl = NButton 'Open selected tool' 20 90 170 30 $true 'Starts the selected tool if it is a graphical program (FTK Imager, KAPE GUI, NetworkMiner, NirSoft viewers and so on).'; $p.Controls.Add($bl)
    $bf = NButton 'Open tools folder' 200 90 160 30; $p.Controls.Add($bf)
    $bl.Add_Click({ if ($g.SelectedRows.Count -ne 1) { Gui-Msg 'Select a tool in the list first.'; return }
        $name = [string]$g.SelectedRows[0].Cells['Tool'].Value; $t = Get-As4Tools | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $t.Path) { Gui-Msg "$name is not installed in the tools folder."; return }
        if (-not $t.Launch -and $t.Id -notin 'ftkimager') { Gui-Msg "$name is a command-line tool. AS4 runs it from the related page."; return }
        Gui-Run { Gui-ShowResults @(Start-As4GuiTool $t.Id) } "Opening $name" }.GetNewClosure())
    $bf.Add_Click({ Start-Process explorer.exe -ArgumentList (ConvertTo-ArgString @($global:P.Tools)) })
    $p }
function Start-As4Gui {
    param([switch]$SkipCaseDialog)
    [Windows.Forms.Application]::EnableVisualStyles()
    $f = New-Object Windows.Forms.Form; $global:G.Form = $f
    $f.Text = "$($global:AS4Name) $($global:AS4Version)"; $f.Size = New-Object Drawing.Size(1280, 860); $f.MinimumSize = New-Object Drawing.Size(1100, 720); $f.StartPosition = 'CenterScreen'; $f.BackColor = $global:C.Bg; $f.ForeColor = $global:C.Text; $f.Font = F 9
    $global:G.Tip = New-Object Windows.Forms.ToolTip; $global:G.Tip.InitialDelay = 300; $global:G.Tip.AutoPopDelay = 20000
    # top bar: wordmark, case, privileges
    $hd = New-Object Windows.Forms.Panel; $hd.Dock = 'Top'; $hd.Height = 52; $hd.BackColor = $global:C.Panel
    $hd.Controls.Add((New-BirdBox 8 8 36)); $hd.Controls.Add((NLabel 'AS4 IR Tool' 52 12 160 28 $global:C.Text (F 13 'Bold')))
    $hd.Controls.Add((NLabel 'CASE' 220 10 60 14 $global:C.Dim (F 7.5 'Bold')))
    $cl = NLabel '' 220 24 420 22 $global:C.Text (F 10 'Bold'); $hd.Controls.Add($cl); $global:G.CaseLabel = $cl
    $pl = NLabel '' 440 17 520 20 $global:C.Dim (F 8.5); $hd.Controls.Add($pl); $global:G.PathLabel = $pl; $cl.Size = New-Object Drawing.Size(210, 22)
    $adm = Test-As4Admin
    $al = NLabel $(if ($adm) { 'Administrator' } else { 'Standard user' }) 840 16 160 22 $(if ($adm) { $global:C.Ok } else { $global:C.Warn }) (F 9 'Bold'); $al.TextAlign = 'MiddleRight'; $al.Anchor = 'Top,Right'; $hd.Controls.Add($al)
    $bo = NButton 'Open folder' 1140 10 100 30; $bo.Anchor = 'Top,Right'; $hd.Controls.Add($bo)
    $bo.Add_Click({ if ($global:Case) { Start-Process explorer.exe -ArgumentList (ConvertTo-ArgString @($global:Case.Dir)) } })
    # bottom: progress + log
    $bt = New-Object Windows.Forms.Panel; $bt.Dock = 'Bottom'; $bt.Height = 150; $bt.BackColor = $global:C.Panel
    $rt = New-Object Windows.Forms.RichTextBox; $rt.Location = New-Object Drawing.Point(10, 36); $rt.Size = New-Object Drawing.Size(1250, 106); $rt.Anchor = 'Top,Left,Right,Bottom'; $rt.BackColor = $global:C.Input; $rt.ForeColor = $global:C.Dim; $rt.ReadOnly = $true; $rt.BorderStyle = 'None'; $rt.Font = New-Object Drawing.Font('Consolas', 9)
    $bar = New-Object Windows.Forms.ProgressBar; $bar.Location = New-Object Drawing.Point(10, 9); $bar.Size = New-Object Drawing.Size(420, 18); $bar.Style = 'Blocks'
    $stl = NLabel 'Ready' 440 9 560 20 $global:C.Dim; $cn = NButton 'Cancel' 1150 4 110 28 $false 'Stops the operation after the running command is ended. Files already written are kept.'; $cn.Anchor = 'Top,Right'; $cn.Enabled = $false
    $cn.Add_Click({ $global:Cancel = $true; Gui-Log WARN 'Cancel requested' })
    $bt.Controls.AddRange(@($rt, $bar, $stl, $cn)); $global:G.Log = $rt; $global:G.Bar = $bar; $global:G.Status = $stl; $global:G.Cancel = $cn
    # navigation
    $nv = New-Object Windows.Forms.Panel; $nv.Dock = 'Left'; $nv.Width = 200; $nv.BackColor = $global:C.Panel; $nv.AutoScroll = $true
    $content = New-Object Windows.Forms.Panel; $content.Dock = 'Fill'
    $qt = @(Get-As4QuickTasks); $tt = @(Get-As4TriageTasks)
    $pages = [ordered]@{
        '@Start' = $null; 'Overview' = { Build-Overview }
        '@Collect' = $null
        'First Response' = { Build-FirstResponsePage }
        'Quick Response' = { New-TaskPage 'Quick Response' 'Live system information using built-in Windows commands. Each button runs one command and saves its output, exit code and hash in the case folder.' $qt 'Collect' }
        'Event Logs' = { Build-EvtxPage }; 'Artifacts' = { Build-ArtifactPage }
        'Persistence' = { New-TaskPage 'Persistence and Malware Triage' 'Processes, services, tasks, autostart entries, WMI subscriptions and recent files. The Leads column is a heuristic for review only. Nothing is stopped or removed.' $tt 'Collect' $false }
        '@Acquire' = $null
        'Memory' = { Build-MemoryPage }; 'Disk Image' = { Build-DiskImagePage }
        '@Analyze' = $null
        'Live Hunt' = { Build-LiveHunt }; 'Parse Files' = { Build-ParsePage }
        'Quick Scan' = { Build-QuickScanPage }; 'Hayabusa' = { Build-HayabusaPage }; 'Hayabusa Advanced' = { Build-HayabusaAdvancedPage }; 'Chainsaw' = { Build-ChainsawPage }; 'KAPE' = { Build-KapePage }; 'IOC, YARA, Timeline' = { Build-AnalysisPage }
        '@Case' = $null
        'Report and Integrity' = { Build-ReportPage }; 'Tools' = { Build-ToolsPage }
    }
    $y = 10
    foreach ($name in $pages.Keys) {
        if ($name.StartsWith('@')) { $y += 4; $nv.Controls.Add((NLabel $name.Substring(1).ToUpper() 16 $y 160 16 $global:C.Dim (F 7.5 'Bold'))); $y += 20; continue }
        $pg = & $pages[$name]; $pg = @($pg)[-1]; $pg.Visible = $false; $content.Controls.Add($pg); $global:G.Pages[$name] = $pg
        $b = New-Object Windows.Forms.Button; $b.Text = '   ' + $name; $b.TextAlign = 'MiddleLeft'; $b.Location = New-Object Drawing.Point(0, $y); $b.Size = New-Object Drawing.Size(184, 25); $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0; $b.BackColor = $global:C.Panel; $b.ForeColor = $global:C.Dim; $b.Font = F 9.5; $b.Cursor = 'Hand'; $b.UseMnemonic = $false
        $nm = $name; $b.Add_Click({ Show-Page $nm }.GetNewClosure()); $nv.Controls.Add($b); $global:G.Nav[$name] = $b; $y += 26
    }
    $f.Controls.Add($content); $f.Controls.Add($nv); $f.Controls.Add($bt); $f.Controls.Add($hd)
    $global:UiLog = { param($l, $m) Gui-Log $l $m }
    $global:UiPump = { [Windows.Forms.Application]::DoEvents() }
    $f.Add_FormClosing({ $global:Cancel = $true })
    $bc = NButton 'Change case' 1030 10 100 30; $bc.Anchor = 'Top,Right'; $hd.Controls.Add($bc)
    $place = { $w = $hd.ClientSize.Width; $bo.Left = $w - $bo.Width - 14; $bc.Left = $bo.Left - $bc.Width - 8; $al.Left = $bc.Left - $al.Width - 12; $al.Top = 15 }.GetNewClosure()
    $hd.Add_Resize($place); $f.Add_Shown($place)
    $bc.Add_Click({ if ($global:G.Busy) { Gui-Msg 'Wait for the running operation to finish.'; return }; if (Show-CaseDialog $global:G.Form) { Update-CaseHeader; Update-Overview; Gui-Log INFO "Case: $($global:Case.Id)" } })
    Show-Page 'Overview'; Update-CaseHeader
    Gui-Log INFO "Root: $($global:P.Root)"
    if (-not $adm) { Gui-Log WARN 'Not running as administrator. Security log, memory capture, KAPE, Prefetch and similar items will be skipped.' }
    $f
}
