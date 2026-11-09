# AS4 IR Tool - Report

# ================= REPORT =================
function HtmlEnc { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

function New-As4Report {
    param([string]$CaseId)
    $dir = Join-Path $global:P.Output $CaseId
    $meta = Get-Content -LiteralPath (Join-Path $dir '00_Metadata\case.json') -Raw | ConvertFrom-Json
    $man = @(Get-As4Manifest $dir)
    $sum = $man | Group-Object Status | ForEach-Object { "<span class='pill $($_.Name)'>$($_.Name): $($_.Count)</span>" }
    $rows = ($man | ForEach-Object {
        "<tr class='$($_.Status)'><td>$(HtmlEnc $_.RunId)</td><td>$(HtmlEnc $_.TaskId)</td><td>$(HtmlEnc $_.Name)</td><td>$(HtmlEnc $_.Status)</td><td>$(HtmlEnc $_.StartUtc)</td><td>$(HtmlEnc $_.EndUtc)</td><td>$(HtmlEnc $_.ExitCode)</td><td class='mono'>$(HtmlEnc ($_.Command + ' ' + $_.Arguments))</td><td>$(HtmlEnc $_.ToolVersion)</td><td>$(HtmlEnc (@($_.Notes) + @($_.Warnings) -join ' | '))</td></tr>" }) -join "`n"
    $hashes = @(); $hf = Join-Path $dir '00_Metadata\hashes.csv'
    if (Test-Path $hf) { $hashes = @(Import-Csv -LiteralPath $hf) }
    $hrows = ($hashes | ForEach-Object { "<tr><td class='mono'>$(HtmlEnc $_.RelativePath)</td><td>$(HtmlEnc $_.Kind)</td><td>$($_.Size)</td><td class='mono'>$(HtmlEnc $_.Sha256)</td></tr>" }) -join "`n"
    $derived = @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\(11_Chainsaw_Analysis|11_Hayabusa_Analysis|12_Reports)\\' -or $_.FullName -match '\\14_Live_Analysis\\(LiveHunt|hunt_findings|LiveWatch|snapshot_changes|SnapshotChanges)' })
    $drows = ($derived | ForEach-Object { "<li class='mono'>$(HtmlEnc (Get-RelPath $_.FullName))</li>" }) -join "`n"
    $tools = @(Get-As4Tools | Where-Object { $_.Status -like 'PRESENT*' })
    $trows = ($tools | ForEach-Object { "<tr><td>$(HtmlEnc $_.Name)</td><td>$(HtmlEnc $_.Status)</td><td>$(HtmlEnc $_.FileVersion)</td><td class='mono'>$(HtmlEnc $_.Path)</td></tr>" }) -join "`n"
    $html = @"
<!doctype html><html><head><meta charset="utf-8"><title>AS4 IR Tool - Report $(HtmlEnc $CaseId)</title><style>
body{background:#0e1318;color:#d7dee5;font:14px Segoe UI,Arial,sans-serif;margin:0;padding:28px}h1{color:#e8eef3;margin:0}h2{border-bottom:1px solid #2a3540;padding-bottom:4px;margin-top:30px;color:#3ddc84}
table{border-collapse:collapse;width:100%;margin:8px 0}td,th{border:1px solid #26313b;padding:4px 7px;text-align:left;vertical-align:top;font-size:12px}th{background:#17202a}
.mono{font-family:Consolas,monospace;word-break:break-all}.pill{display:inline-block;padding:2px 9px;border-radius:10px;margin-right:6px;background:#26313b}.pill.OK{background:#1f5c3a}.pill.FAILED,.pill.TIMEOUT{background:#7a2b2b}.pill.SKIPPED,.pill.CANCELLED{background:#7a6a22}
tr.FAILED td:nth-child(4),tr.TIMEOUT td:nth-child(4){color:#ff8a8a}tr.OK td:nth-child(4){color:#7fe0a0}tr.SKIPPED td:nth-child(4){color:#f0d070}.note{background:#17202a;border-left:3px solid #d29b38;padding:8px 12px}
</style></head><body>
<h1>$(Get-As4BirdSvg 30) AS4 IR Tool - Collection Report</h1><div>Case <b>$(HtmlEnc $CaseId)</b> - generated $(Get-UtcIso) UTC by AS4 IR Tool v$($global:AS4Version) on $(HtmlEnc $env:COMPUTERNAME)</div>
<h2>Case</h2><table>
<tr><th>Case name</th><td>$(HtmlEnc $meta.CaseName)</td><th>Created (UTC)</th><td>$(HtmlEnc $meta.CreatedUtc)</td></tr>
<tr><th>Analyst</th><td>$(HtmlEnc $meta.Analyst)</td><th>Analyst workstation</th><td>$(HtmlEnc $meta.AnalystWorkstation)</td></tr></table>
<div class="note"><b>Interpretation notice.</b> This report lists what AS4 collected and what tools reported. Heuristic leads and rule matches (Sigma/YARA/IOC) are <b>triage leads, not confirmed compromise</b>; conclusions are the analyst's.</div>
<h2>Operation summary</h2><p>$($sum -join ' ')</p>
<table><tr><th>Run</th><th>Task</th><th>Name</th><th>Status</th><th>Start UTC</th><th>End UTC</th><th>Exit</th><th>Command / arguments</th><th>Tool version</th><th>Notes / warnings</th></tr>
$rows</table>
<h2>Bundled tools detected</h2><table><tr><th>Tool</th><th>Status</th><th>File version</th><th>Path</th></tr>$trows</table>
<h2>Derived results (analysis output, separate from raw evidence)</h2><ul>$drows</ul>
<h2>Evidence hash ledger (SHA-256)</h2><table><tr><th>File</th><th>Kind</th><th>Bytes</th><th>SHA-256</th></tr>$hrows</table>
</body></html>
"@
    $out = Get-UniquePath (Join-Path $dir '12_Reports') 'AS4_report' 'html'
    Write-As4File $out $html
    $csv = Get-UniquePath (Join-Path $dir '12_Reports') 'AS4_operations' 'csv'
    $man | Select-Object RunId,TaskId,Name,Category,Status,StartUtc,EndUtc,ExitCode,Command,Arguments,ToolVersion,@{n='Destination';e={@($_.Destination) -join ';'}},@{n='Sha256';e={@($_.Sha256) -join ';'}},@{n='Notes';e={@($_.Notes) -join ' | '}},@{n='Warnings';e={@($_.Warnings) -join ' | '}} | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $js = Get-UniquePath (Join-Path $dir '12_Reports') 'AS4_summary' 'json'
    Write-As4File $js ([ordered]@{ Case = $meta; Generated = Get-UtcIso; Counts = (Get-As4Summary $dir); Operations = $man } | ConvertTo-Json -Depth 8)
    # report files are derived outputs; hash them into the ledger when this case is active
    if ($global:Case -and $global:Case.Id -eq $CaseId) { $global:RunId = $(if ($global:RunId) { $global:RunId } else { 'REPORT-' + (Get-UtcStamp) }); Register-As4Files @($out, $csv, $js) 'derived' | Out-Null }
    [pscustomobject]@{ Html = $out; Csv = $csv; Json = $js }
}
