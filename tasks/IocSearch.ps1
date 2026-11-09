# AS4 IR Tool - IocSearch

# ================= IOC SEARCH =================
function Get-IocType {
    param([string]$v)
    if ($v -match '^[a-fA-F0-9]{64}$') { 'sha256' } elseif ($v -match '^[a-fA-F0-9]{40}$') { 'sha1' } elseif ($v -match '^[a-fA-F0-9]{32}$') { 'md5' }
    elseif ($v -match '^\d{1,3}(\.\d{1,3}){3}$') { 'ipv4' } elseif ($v -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { 'url' }
    elseif ($v -match '^[A-Za-z]:\\|^\\\\|^/') { 'path' } elseif ($v -match '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') { 'domain' } else { 'string' }
}

function Invoke-As4IocSearch {
    param([Parameter(Mandatory)][string]$IocFile, [Parameter(Mandatory)][string]$SearchRoot, [string[]]$Extensions = @('txt','csv','json','log','xml','reg','ini','ps1','bat','cmd','vbs','js','html','htm','md','tsv','jsonl'), [double]$MaxMB = 200)
    if (-not (Test-Path -LiteralPath $IocFile -PathType Leaf)) { throw "IOC list not found: $IocFile" }
    if (-not (Test-Path -LiteralPath $SearchRoot)) { throw "Search root not found: $SearchRoot" }
    $iocs = @(Get-Content -LiteralPath $IocFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -Unique)
    if (-not $iocs.Count) { throw 'IOC list is empty.' }
    $types = @{}; foreach ($i in $iocs) { $types[$i.ToLower()] = Get-IocType $i }
    $rx = New-Object Text.RegularExpressions.Regex(('(' + (($iocs | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'), 'IgnoreCase,Compiled')
    $e = New-As4Entry 'ioc_search' 'IOC search (offline)' $global:CaseFolders.Rep 'collected files'
    $e.Command = 'AS4 IOC search'; $e.Arguments = "iocs=$($iocs.Count) root=$SearchRoot"
    $hits = New-Object Collections.ArrayList; $scope = @(); $skipped = @()
    $files = Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Force -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if ($global:Cancel) { break }
        $ext = $f.Extension.TrimStart('.').ToLower()
        if ($Extensions -notcontains $ext) { $skipped += [pscustomobject]@{ File = $f.FullName; Reason = "extension .$ext not text-searchable (binary files such as .evtx must be converted first)" }; continue }
        if ($f.Length -gt $MaxMB * 1MB) { $skipped += [pscustomobject]@{ File = $f.FullName; Reason = "larger than $MaxMB MB" }; continue }
        $scope += $f.FullName
        try {
            $fs = New-Object IO.FileStream($f.FullName, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8, $true); $n = 0
            while (($line = $sr.ReadLine()) -ne $null) { $n++
                $m = $rx.Matches($line)
                foreach ($x in $m) { $ctx = if ($line.Length -gt 300) { $line.Substring([Math]::Max(0, $x.Index - 100), [Math]::Min(300, $line.Length - [Math]::Max(0, $x.Index - 100))) } else { $line }
                    [void]$hits.Add([pscustomobject]@{ IOC = $x.Value; Type = $types[$x.Value.ToLower()]; SourceFile = $f.FullName; Line = $n; Context = $ctx }) } }
            $sr.Dispose()
        } catch { $skipped += [pscustomobject]@{ File = $f.FullName; Reason = $_.Exception.Message } }
    }
    $rep = Get-CaseFolder 'Rep'
    $hf = Get-UniquePath $rep 'ioc_hits' 'csv'; $hits | Export-Csv -LiteralPath $hf -NoTypeInformation -Encoding UTF8
    $sf = Get-UniquePath $rep 'ioc_scope' 'csv'; (@($scope | ForEach-Object { [pscustomobject]@{ File = $_; State = 'SCANNED'; Reason = '' } }) + @($skipped | ForEach-Object { [pscustomobject]@{ File = $_.File; State = 'SKIPPED'; Reason = $_.Reason } })) | Export-Csv -LiteralPath $sf -NoTypeInformation
    $e.Status = if ($global:Cancel) { 'CANCELLED' } else { 'OK' }
    $e.Notes += "$($hits.Count) match(es) across $($scope.Count) scanned file(s); $($skipped.Count) skipped. A match is a lead, not proof of compromise."
    Start-As4Run 'ioc' | Out-Null
    Complete-As4Entry $e @($hf, $sf) 'derived' | Out-Null
    Stop-As4Run
    [pscustomobject]@{ Hits = $hits.Count; Scanned = $scope.Count; Skipped = $skipped.Count; HitsFile = $hf; ScopeFile = $sf }
}
