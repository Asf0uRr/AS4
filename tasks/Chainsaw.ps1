# AS4 IR Tool - Chainsaw

$global:ChainsawCache = $null

function Get-ChainsawInfo {
    param([switch]$Refresh)
    if ($global:ChainsawCache -and -not $Refresh) { return $global:ChainsawCache }
    $t = Get-As4Tool 'chainsaw'
    $info = [ordered]@{ Present = $false; Path = $null; Dir = $null; Runnable = $false; Version = $null; BlockReason = $null; Help = @{}; Flags = @{}; Sigma = $null; Rules = $null; Mappings = @() }
    if ($t -and $t.Path) {
        $info.Present = $true; $info.Path = $t.Path; $info.Dir = Split-Path $t.Path
        foreach ($c in @('sigma', 'rules', 'mappings')) { }
        $sg = Join-Path $info.Dir 'sigma'; if (Test-Path $sg) { $info.Sigma = $sg }
        $rl = Join-Path $info.Dir 'rules'; if (Test-Path $rl) { $info.Rules = $rl }
        $mp = Join-Path $info.Dir 'mappings'; if (Test-Path $mp) { $info.Mappings = @(Get-ChildItem $mp -Filter *.yml | ForEach-Object { $_.FullName }) }
        $v = Invoke-As4Native -Exe $info.Path -Arguments @('--version') -TimeoutSec 30
        if ($v.Error) { $info.BlockReason = $v.Error }
        elseif ($v.ExitCode -eq 0) { $info.Runnable = $true; $info.Version = ($v.StdOut + $v.StdErr).Trim() }
        else { $info.BlockReason = "exit=$($v.ExitCode) $($v.StdErr)" }
        if ($info.Runnable) {
            foreach ($sub in @('', 'hunt', 'search')) {
                $a = if ($sub) { @($sub, '--help') } else { @('--help') }
                $h = Invoke-As4Native -Exe $info.Path -Arguments $a -TimeoutSec 30
                $txt = ($h.StdOut + "`n" + $h.StdErr)
                $key = if ($sub) { $sub } else { 'main' }
                $info.Help[$key] = $txt
                $info.Flags[$key] = @([regex]::Matches($txt, '--[a-z][a-z0-9-]*') | ForEach-Object { $_.Value } | Select-Object -Unique)
            }
        }
    }
    $global:ChainsawCache = [pscustomobject]$info
    $global:ChainsawCache
}

function Get-ChainsawProfiles {
    $ci = Get-ChainsawInfo
    $profs = @()
    foreach ($f in (Get-ChildItem $global:P.Profiles -Filter 'chainsaw_*.json' -ErrorAction SilentlyContinue)) { $profs += (Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json) }
    $profs
}

function Resolve-ChainsawRel { param($Dir, [string]$p) if (-not $p) { return $null }; $full = Join-Path $Dir $p; if (Test-Path -LiteralPath $full) { $full } else { $null } }

function Build-ChainsawArgs {
    # Only emits a flag if the installed Chainsaw's own help lists it. Returns args + skipped notes.
    param([string]$Sub, [hashtable]$O)
    $ci = Get-ChainsawInfo; $fl = @($ci.Flags[$Sub]); $a = @($Sub); $notes = @()
    function Has($f) { $fl -contains $f }
    if ($Sub -eq 'hunt') {
        foreach ($s in @($O.Sigma)) { if ($s) { if (Has '--sigma') { $a += @('--sigma', $s) } else { $notes += '--sigma not in installed help; skipped' } } }
        foreach ($r in @($O.Rules)) { if ($r) { if (Has '--rule') { $a += @('--rule', $r) } else { $notes += '--rule not in installed help; skipped' } } }
        foreach ($m in @($O.Mapping)) { if ($m) { if (Has '--mapping') { $a += @('--mapping', $m) } else { $notes += '--mapping not in installed help; skipped' } } }
        foreach ($l in @($O.Level)) { if ($l) { if (Has '--level') { $a += @('--level', $l) } else { $notes += '--level unsupported; skipped' } } }
        if ($O.Full) { if (Has '--full') { $a += '--full' } }
        if ($O.Format -eq 'csv') { if (Has '--csv') { $a += '--csv' } else { $notes += '--csv unsupported' } }
        if ($O.Format -eq 'json') { if (Has '--json') { $a += '--json' } else { $notes += '--json unsupported' } }
        if ($O.Format -eq 'log') { if (Has '--log') { $a += '--log' } else { $notes += '--log unsupported' } }
    } else {
        if ($O.IgnoreCase) { if (Has '--ignore-case') { $a += '--ignore-case' } }
        if ($O.Format -eq 'json') { if (Has '--json') { $a += '--json' } else { $notes += '--json unsupported' } }
        if ($O.Pattern) { if (Has '--regex') { $a += @('--regex', $O.Pattern) } else { $a += $O.Pattern } }
    }
    if ($O.From) { if (Has '--from') { $a += @('--from', $O.From) } else { $notes += '--from unsupported' } }
    if ($O.To) { if (Has '--to') { $a += @('--to', $O.To) } else { $notes += '--to unsupported' } }
    if ($O.SkipErrors) { if (Has '--skip-errors') { $a += '--skip-errors' } }
    if ($O.LoadUnknown) { if (Has '--load-unknown') { $a += '--load-unknown' } }
    if ($O.Output) { if (Has '--output') { $a += @('--output', $O.Output) } else { $notes += '--output unsupported' } }
    foreach ($i in @($O.Input)) { $a += $i }
    [pscustomobject]@{ Args = $a; Notes = $notes }
}

function Invoke-Chainsaw {
    param([ValidateSet('hunt', 'search')][string]$Sub, [hashtable]$O)
    $ci = Get-ChainsawInfo -Refresh
    $e = New-As4Entry "chainsaw_$Sub" "Chainsaw $Sub" $global:CaseFolders.Chain 'selected EVTX'
    Start-As4Run "chainsaw-$Sub" | Out-Null
    $files = @()
    try {
        if (-not $ci.Present) { $e.Status = 'SKIPPED'; $e.Notes += 'Chainsaw not found under tools\Chainsaw.'; return (Complete-As4Entry $e @()) }
        if (-not $ci.Runnable) { $e.Status = 'SKIPPED'; $e.Notes += "Chainsaw cannot execute on this machine: $($ci.BlockReason)"; if (Test-BlockedMessage $ci.BlockReason) { $e.Notes += 'The host application-control policy blocks the binary. AS4 does not bypass security controls; have the policy owner allow it or run on a permitted workstation.' }; return (Complete-As4Entry $e @()) }
        if (-not $O.Input -or -not @($O.Input).Count) { throw 'No input EVTX file or directory selected.' }
        foreach ($i in @($O.Input)) { if (-not (Test-Path -LiteralPath $i)) { throw "Input not found: $i" } }
        $runDir = Join-Path (Get-CaseFolder 'Chain') ("{0}_{1}" -f $global:RunId, $Sub); New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $O = @{} + $O
        if ($O.Format -in 'csv') { $O.Output = Join-Path $runDir 'results_csv' } elseif ($O.Format -eq 'json') { $O.Output = Join-Path $runDir 'results.json' }
        $b = Build-ChainsawArgs $Sub $O
        $e.Command = $ci.Path; $e.Arguments = (ConvertTo-ArgString $b.Args); $e.ToolVersion = $ci.Version
        foreach ($n in $b.Notes) { $e.Warnings += $n }
        $r = Invoke-As4Native -Exe $ci.Path -Arguments $b.Args -TimeoutSec 3600 -WorkDir $ci.Dir
        $e.ExitCode = $r.ExitCode; $e.StartUtc = $r.StartUtc
        $so = Join-Path $runDir 'raw_stdout.txt'; Write-As4File $so $r.StdOut; $files += $so
        $se = Join-Path $runDir 'raw_stderr.txt'; Write-As4File $se $r.StdErr; $files += $se
        $af = Join-Path $runDir 'arguments.json'; Write-As4File $af ([ordered]@{ Executable = $ci.Path; Version = $ci.Version; Subcommand = $Sub; Arguments = $b.Args; CommandLine = $e.Arguments; Skipped = $b.Notes; StartUtc = $r.StartUtc; EndUtc = $r.EndUtc } | ConvertTo-Json -Depth 4); $files += $af
        $hf = Join-Path $runDir 'chainsaw_help_snapshot.txt'; Write-As4File $hf (($ci.Help.GetEnumerator() | ForEach-Object { "=== $($_.Key) ===`r`n$($_.Value)" }) -join "`r`n"); $files += $hf
        foreach ($x in @(Get-ChildItem -LiteralPath $runDir -Recurse -File | Where-Object { $files -notcontains $_.FullName })) { $files += $x.FullName }
        $e.Status = Get-As4OpStatusFromResult $r
        if ($r.Error) { $e.Notes += $r.Error }
        if ($e.Status -eq 'OK') { $e.Notes += 'Chainsaw reported rule matches as tool findings (leads); they are not confirmed compromise.' }
        else { $e.Notes += "exit=$($r.ExitCode)" }
    } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message }
    $res = Complete-As4Entry $e $files 'derived'
    Stop-As4Run
    $res
}

function Import-ChainsawResults {
    # Defensive loader for Chainsaw JSON/CSV output. Field names differ by version; unknown shapes are shown raw.
    param([string]$Path)
    $out = @()
    $items = if (Test-Path -LiteralPath $Path -PathType Container) { Get-ChildItem -LiteralPath $Path -Recurse -File -Include *.csv, *.json } else { @(Get-Item -LiteralPath $Path) }
    foreach ($f in $items) {
        if ($f.Extension -eq '.csv') { foreach ($r in (Import-Csv -LiteralPath $f.FullName)) { $r | Add-Member -NotePropertyName SourceFile -NotePropertyValue $f.Name -Force -PassThru | ForEach-Object { $out += $_ } } }
        elseif ($f.Extension -eq '.json') {
            $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($d in @($j)) {
                $name = if ($d.name) { $d.name } elseif ($d.rule) { $d.rule } else { '' }
                $out += [pscustomobject]@{ Timestamp = $d.timestamp; Detection = $name; Level = $d.level; Status = $d.status; Group = $d.group; Kind = $d.kind; Count = $d.count; Authors = ($d.authors -join ','); SourceFile = $f.Name; Raw = ($d | ConvertTo-Json -Depth 3 -Compress) }
            }
        }
    }
    $out
}
