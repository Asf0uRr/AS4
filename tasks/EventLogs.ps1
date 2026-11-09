# AS4 IR Tool - EventLogs

# ================= EVENT LOGS =================
function Get-As4EvtxChannels {
    @(
    @{ Name='System'; Group='Core'; Desc='System events: service installs (7045), crashes, shutdowns.' }
    @{ Name='Application'; Group='Core'; Desc='Application errors and AV/app events.' }
    @{ Name='Security'; Group='Core'; Desc='Logons (4624/4625), process creation (4688), account changes. Requires administrator.'; Admin=$true }
    @{ Name='Windows PowerShell'; Group='PowerShell'; Desc='Classic PowerShell engine log.' }
    @{ Name='Microsoft-Windows-PowerShell/Operational'; Group='PowerShell'; Desc='Script block logging (4104) and module logging if enabled.' }
    @{ Name='Microsoft-Windows-Sysmon/Operational'; Group='Sysmon'; Desc='Sysmon telemetry (only if Sysmon is installed on the target).' }
    @{ Name='Microsoft-Windows-Windows Defender/Operational'; Group='Defender'; Desc='Defender detections, protection changes (5001/5007).' }
    @{ Name='Microsoft-Windows-TaskScheduler/Operational'; Group='Persistence'; Desc='Task registration/execution (106,200,201) if enabled.' }
    @{ Name='Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; Group='RDP'; Desc='RDP session logon/logoff/reconnect (21,22,23,24,25).' }
    @{ Name='Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'; Group='RDP'; Desc='RDP connection attempts (1149).' }
    @{ Name='Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'; Group='RDP'; Desc='RDP core transport events.' }
    @{ Name='Microsoft-Windows-TerminalServices-RDPClient/Operational'; Group='RDP'; Desc='Outbound RDP client connections from this host.' }
    @{ Name='Microsoft-Windows-WinRM/Operational'; Group='Remote'; Desc='WinRM / PowerShell remoting.' }
    @{ Name='Microsoft-Windows-Windows Firewall With Advanced Security/Firewall'; Group='Firewall'; Desc='Firewall rule changes.' }
    @{ Name='Microsoft-Windows-WMI-Activity/Operational'; Group='Persistence'; Desc='WMI activity incl. subscriptions (5857-5861).' }
    @{ Name='Microsoft-Windows-Bits-Client/Operational'; Group='Other'; Desc='BITS transfers (download abuse).' }
    @{ Name='Microsoft-Windows-DNS-Client/Operational'; Group='Other'; Desc='DNS client queries (if enabled).' }
    @{ Name='Microsoft-Windows-SMBServer/Security'; Group='Remote'; Desc='Inbound SMB security events.' }
    @{ Name='Microsoft-Windows-SMBClient/Security'; Group='Remote'; Desc='Outbound SMB security events.' }
    @{ Name='Microsoft-Windows-NTLM/Operational'; Group='Other'; Desc='NTLM usage auditing if enabled.' }
    @{ Name='Microsoft-Windows-CodeIntegrity/Operational'; Group='Other'; Desc='Driver/binary signing violations.' }
    @{ Name='Microsoft-Windows-AppLocker/EXE and DLL'; Group='Other'; Desc='AppLocker decisions if configured.' }
    )
}

function Test-As4Channel { param([string]$Name) $r = Invoke-As4Native -Exe 'wevtutil.exe' -Arguments @('gl', $Name) -TimeoutSec 30; ($r.ExitCode -eq 0) }

function New-As4EvtxQuery {
    param([datetime]$StartUtc, [datetime]$EndUtc, [string]$EventIds)
    $c = @()
    if ($EventIds) {
        $ids = @($EventIds -split '[,;\s]+' | Where-Object { $_ })
        foreach ($i in $ids) { if ($i -notmatch '^\d{1,5}$') { throw "Invalid event ID '$i' (digits only)." } }
        if ($ids.Count) { $c += '(' + (($ids | ForEach-Object { "EventID=$_" }) -join ' or ') + ')' }
    }
    $t = @()
    if ($StartUtc) { $t += "@SystemTime>='" + $StartUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z') + "'" }
    if ($EndUtc) { $t += "@SystemTime<='" + $EndUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z') + "'" }
    if ($t.Count) { $c += 'TimeCreated[' + ($t -join ' and ') + ']' }
    if (-not $c.Count) { return $null }
    '*[System[' + ($c -join ' and ') + ']]'
}

function Export-As4Evtx {
    # Exports with wevtutil epl. Unfiltered => original EVTX (05_Event_Logs\raw_evtx). Filtered => derived (05_Event_Logs\filtered_evtx).
    param([string[]]$Channels, [string]$Query, [scriptblock]$OnProgress)
    $filtered = [bool]$Query
    $sub = if ($filtered) { 'filtered_evtx' } else { 'raw_evtx' }
    $dir = Join-Path (Get-CaseFolder 'Evtx') $sub
    Start-As4Run "evtx-$sub" | Out-Null
    $admin = Test-As4Admin; $i = 0; $out = @(); $meta = @()
    foreach ($ch in $Channels) {
        $i++; if ($OnProgress) { & $OnProgress $i $Channels.Count $ch }
        $e = New-As4Entry ('evtx:' + $ch) ("Export $ch" + $(if ($filtered) { ' (FILTERED - derived)' } else { ' (original EVTX)' })) $global:CaseFolders.Evtx
        try {
            if ($global:Cancel) { $e.Status = 'CANCELLED'; $e.Notes += 'Cancelled by analyst.'; Complete-As4Entry $e @() | Out-Null; continue }
            if ($ch -eq 'Security' -and -not $admin) { $e.Status = 'SKIPPED'; $e.Notes += 'Security log requires administrator.'; Complete-As4Entry $e @() | Out-Null; continue }
            if (-not (Test-As4Channel $ch)) { $e.Status = 'SKIPPED'; $e.Notes += 'Channel does not exist on this system.'; Complete-As4Entry $e @() | Out-Null; continue }
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $dest = Get-UniquePath $dir ($ch -replace '/', '%4') 'evtx'
            $a = @('epl', $ch, $dest)
            if ($Query) { $a += "/q:$Query" }
            $r = Invoke-As4Native -Exe 'wevtutil.exe' -Arguments $a -TimeoutSec 900
            $e.Command = $r.Exe; $e.Arguments = $r.ArgString; $e.ExitCode = $r.ExitCode; $e.StartUtc = $r.StartUtc
            $e.ToolVersion = 'wevtutil (Windows built-in)'
            $e.Source = "live channel: $ch"
            if ($r.Cancelled) { $e.Status = 'CANCELLED'; $e.Notes += 'Cancelled; any partial file is not trusted.' }
            elseif ($r.TimedOut) { $e.Status = 'TIMEOUT' }
            elseif ($r.ExitCode -eq 0 -and (Test-Path -LiteralPath $dest) -and (Get-Item -LiteralPath $dest).Length -gt 0) { $e.Status = 'OK'; $out += $dest }
            else {
                $e.Status = 'FAILED'
                if ($r.StdErr -match '(?i)access is denied|^\s*5\b' -or $r.ExitCode -eq 5) { $e.Notes += 'Access denied - run elevated.' }
                $e.Notes += ("wevtutil exit=$($r.ExitCode) $($r.StdErr.Trim())")
            }
            if ($e.Status -ne 'OK' -and (Test-Path -LiteralPath $dest)) { $e.Warnings += 'Discarded/partial output file left in place and not trusted: ' + (Get-RelPath $dest); $out += $dest }
            if ($filtered) { $e.Notes += "Filtered by query: $Query" }
            # metadata
            $m = Invoke-As4Native -Exe 'wevtutil.exe' -Arguments @('gli', $ch) -TimeoutSec 30
            if ($m.ExitCode -eq 0) { $meta += "### $ch`r`n$($m.StdOut)" }
            Complete-As4Entry $e @($dest) | Out-Null
        } catch { $e.Status = 'FAILED'; $e.Notes += $_.Exception.Message; Complete-As4Entry $e @() | Out-Null }
    }
    if ($meta.Count) {
        $mf = Get-UniquePath (Get-CaseFolder 'Evtx') 'channel_metadata' 'txt'
        Write-As4File $mf ("# wevtutil gli output (log metadata) - run $($global:RunId)`r`n" + ($meta -join "`r`n"))
        Register-As4Files @($mf) 'derived' | Out-Null
    }
    Stop-As4Run
    , @($out)
}
