# AS4 IR Tool - Timeline

# ================= TIMELINE =================
function Invoke-As4Timeline {
    $caseDir = $global:Case.Dir
    $rows = New-Object Collections.ArrayList
    $re = '(?i)(time|date|created|modified|accessed|start|boot|logon|detect)'
    foreach ($f in (Get-ChildItem -LiteralPath $caseDir -Recurse -File -Filter *.csv -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(00_Metadata|12_Reports|13_Collection_Logs)\\' -and $_.Length -lt 200MB })) {
        $rel = Get-RelPath $f.FullName
        try { $data = Import-Csv -LiteralPath $f.FullName -ErrorAction Stop } catch { continue }
        if (-not $data) { continue }
        $cols = @($data[0].PSObject.Properties.Name | Where-Object { $_ -match $re })
        if (-not $cols.Count) { continue }
        $lab = @($data[0].PSObject.Properties.Name | Where-Object { $_ -match '^(Name|Path|Source|CommandLine|ProcessName|TaskName|Command|FullName|Process)$' } | Select-Object -First 1)
        foreach ($d in $data) {
            foreach ($c in $cols) {
                $v = $d.$c; if (-not $v) { continue }
                $dt = [datetime]::MinValue; $utc = $null; $conf = ''
                if ($v -match '(Z|[+-]\d{2}:?\d{2})$' -and [datetime]::TryParse($v, [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal,AssumeUniversal', [ref]$dt)) { $utc = $dt; $conf = 'High: source carries explicit UTC/offset' }
                elseif ([datetime]::TryParse($v, [Globalization.CultureInfo]::InvariantCulture, 'AssumeLocal,AdjustToUniversal', [ref]$dt)) { $utc = $dt; $conf = 'UNCERTAIN: no zone in source; assumed analysis-host local time (verify target time zone from datetime task)' }
                else { continue }
                [void]$rows.Add([pscustomobject]@{ TimestampUtc = $utc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); TimeField = $c; OriginalValue = $v; Description = $(if ($lab) { $d.($lab[0]) } else { '' }); SourceFile = $rel; Confidence = $conf })
            }
        }
    }
    $sorted = $rows | Sort-Object TimestampUtc
    $out = Get-UniquePath (Get-CaseFolder 'Rep') 'timeline_utc' 'csv'
    $sorted | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
    Start-As4Run 'timeline' | Out-Null
    $e = New-As4Entry 'timeline' 'Timeline preparation (derived)' $global:CaseFolders.Rep 'collected CSV metadata'
    $e.Status = 'OK'; $e.Command = 'AS4 timeline'; $e.Notes += "$($rows.Count) timestamp row(s) from collected CSVs. Original values preserved in OriginalValue; see Confidence column."
    Complete-As4Entry $e @($out) 'derived' | Out-Null; Stop-As4Run
    [pscustomobject]@{ Rows = $rows.Count; File = $out }
}
