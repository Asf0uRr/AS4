# AS4 IR Tool - Yara

# ================= YARA =================
function New-YaraIndex {
    # Builds one rules file from a folder of .yar files. Files that do not compile are left out and listed.
    param([string]$Dir, [string]$OutDir)
    $c = Get-As4Tool 'yara'; $yarac = Join-Path (Split-Path $c.Path) 'yarac64.exe'
    $ok = @(); $bad = @(); $wk = Join-Path $global:P.Output '_work'; if (-not (Test-Path -LiteralPath $wk)) { New-Item -ItemType Directory -Path $wk -Force | Out-Null }; $tmp = Join-Path $wk ('as4_yc_' + [guid]::NewGuid().ToString('N') + '.bin')
    foreach ($f in (Get-ChildItem -LiteralPath $Dir -Recurse -File -Include *.yar, *.yara)) {
        if (Test-Path -LiteralPath $yarac) {
            $r = Invoke-As4Native -Exe $yarac -Arguments @($f.FullName, $tmp) -TimeoutSec 60
            if ($r.ExitCode -eq 0) { $ok += $f.FullName } else { $bad += [pscustomobject]@{ File = $f.FullName; Error = ($r.StdErr.Trim() -split "`n")[0] } }
        } else { $ok += $f.FullName }
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $idx = Get-UniquePath $OutDir 'yara_rules_index' 'yar'
    Write-As4File $idx (($ok | ForEach-Object { 'include "' + ($_ -replace '\\', '/') + '"' }) -join "`r`n")
    [pscustomobject]@{ Index = $idx; Compiled = $ok.Count; Skipped = $bad }
}
function Invoke-Yara {
    param([string]$Rules, [string]$Target)
    $t = Get-As4Tool 'yara'
    $e = New-As4Entry 'yara_scan' 'YARA scan' $global:CaseFolders.Rep 'selected evidence'
    Start-As4Run 'yara' | Out-Null; $files = @()
    try {
        if (-not $t -or -not $t.Path) { $e.Status = 'SKIPPED'; $e.Notes += 'YARA executable not found under tools\YARA (yara64.exe/yara.exe).'; return (Complete-As4Entry $e @()) }
        foreach ($p in $Rules, $Target) { if (-not (Test-Path -LiteralPath $p)) { throw "Not found: $p" } }
        if (Test-Path -LiteralPath $Rules -PathType Container) { $ix = New-YaraIndex $Rules (Get-CaseFolder 'Rep'); $files += $ix.Index; $Rules = $ix.Index; $e.Notes += "Rule folder: $($ix.Compiled) rule files used, $(@($ix.Skipped).Count) skipped (did not compile)."; if (@($ix.Skipped).Count) { $sk = Get-UniquePath (Get-CaseFolder 'Rep') 'yara_rules_skipped' 'csv'; $ix.Skipped | Export-Csv -LiteralPath $sk -NoTypeInformation; $files += $sk } }
        $h = Invoke-As4Native -Exe $t.Path -Arguments @('--help') -TimeoutSec 20
        $helpTxt = $h.StdOut + $h.StdErr
        $a = @(); if ((Test-Path -LiteralPath $Target -PathType Container) -and $helpTxt -match '--recursive') { $a += '--recursive' }
        $a += @($Rules, $Target)
        $listing = if (Test-Path -LiteralPath $Target -PathType Container) { @(Get-ChildItem -LiteralPath $Target -Recurse -File -Force -ErrorAction SilentlyContinue) } else { @(Get-Item -LiteralPath $Target) }
        $e.Command = $t.Path; $e.Arguments = ConvertTo-ArgString $a; $e.ToolVersion = ($h.StdOut + $h.StdErr).Split("`n")[0].Trim()
        $r = Invoke-As4Native -Exe $t.Path -Arguments $a -TimeoutSec 3600
        $rep = Get-CaseFolder 'Rep'
        $of = Get-UniquePath $rep 'yara_matches' 'txt'; Write-As4File $of $r.StdOut; $files += $of
        $lf = Get-UniquePath $rep 'yara_log' 'txt'; Write-As4File $lf ("cmd: $($t.Path) $($e.Arguments)`r`nexit: $($r.ExitCode)`r`nfiles in scope: $($listing.Count)`r`n--- stderr (skipped/unreadable items appear here) ---`r`n$($r.StdErr)"); $files += $lf
        $sf = Get-UniquePath $rep 'yara_scope' 'csv'; $listing | Select-Object FullName, Length, LastWriteTimeUtc | Export-Csv -LiteralPath $sf -NoTypeInformation; $files += $sf
        $e.ExitCode = $r.ExitCode; $e.Status = Get-As4OpStatusFromResult $r
        $e.Notes += "$($listing.Count) file(s) in scope; matches are leads, not verdicts."
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e $files 'derived'; Stop-As4Run; $res
}
