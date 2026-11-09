# AS4 IR Tool - Integrity

# ================= INTEGRITY =================
function Invoke-As4Verify {
    param([string]$CaseId)
    $dir = Join-Path $global:P.Output $CaseId
    $res = @(Test-As4Hashes $dir)
    $bad = @($res | Where-Object Status -ne 'OK')
    $rep = Join-Path $dir ("12_Reports\integrity_verification_{0}.csv" -f (Get-UtcStamp))
    if (-not (Test-Path (Split-Path $rep))) { New-Item -ItemType Directory -Path (Split-Path $rep) -Force | Out-Null }
    $res | Export-Csv -LiteralPath $rep -NoTypeInformation
    [pscustomobject]@{ Total = $res.Count; OK = ($res.Count - $bad.Count); Problems = $bad.Count; Report = $rep; Details = $bad }
}
