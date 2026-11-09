# Live analysis and First Response

Everything on this page runs from the AS4 folder, needs no installation on the machine you examine, makes no network connection of its own and only reads. Output goes to `output\<case>\14_Live_Analysis\`.

## Live Hunt

Question it answers: *does anything on this running machine deserve attention, and what do I do about it?*

| Area | What it looks at |
|---|---|
| Processes | Core Windows processes (`lsass`, `services`, `svchost`, `winlogon`...) in the wrong folder, with the wrong parent, or running twice; names one letter off a Windows name; Office, PDF readers, web and database servers starting a shell; command lines with encoded PowerShell, download cradles, `certutil`/`bitsadmin`/`mshta`/`regsvr32`/`rundll32` abuse, LSASS dumping, backup deletion, log clearing, account creation; programs whose file is gone from disk; unsigned or invalid-signature programs in temp, Public, Downloads, AppData and ProgramData |
| Network | Programs that rarely use the network but are connected to the internet; unsigned programs from writable folders talking out or listening; ports often used by backdoors and Tor |
| Services and drivers | Services that start shells or script hosts; unsigned programs or `ServiceDll` files in writable folders; unquoted paths; kernel drivers that are not validly signed |
| Persistence | Run/RunOnce, Startup folders, scheduled tasks, WMI subscriptions, Image File Execution Options and SilentProcessExit, Winlogon Shell/Userinit, AppInit_DLLs, AppCertDlls, BootExecute, logon scripts, LSA packages, per-user COM hijacks, replaced accessibility programs (`sethc`, `utilman`...) |
| Accounts | Local users (hidden `$` names, enabled Guest, no password required) and the Administrators group |
| Defences | Defender state and exclusions, other antivirus products, firewall profiles, RDP and NLA, UAC, WDigest, SMB1, port forwarding, proxies, DNS servers, hosts file |
| Known tools | Names of attack and dual-use tools in running programs, services, installed software, Prefetch and autostarts; Cobalt Strike style named pipes |
| Event logs | Services installed, logs cleared, Defender detections and shut-offs, RDP logons from internet addresses, PowerShell script blocks (AMSI bypass, in-memory loading), failed-logon storms followed by a success, new accounts and privileged group changes (Security log needs administrator) |
| Files | Unsigned programs and libraries created in the last days in writable folders; recently created scripts (time-boxed so it stays gentle) |
| Evidence readiness | Which logs are on, how many records they hold and how far back they go, and whether command lines and script blocks are being recorded |

### How to read the result

- **Verdict** in plain words: *Nothing stood out*, *A few things to review*, *Worth a closer look*, *Strong leads*, *Many strong leads*. A single high-severity lead is never shown as green.
- Each lead has: what was seen, **why it matters**, **what to do next**, and the MITRE ATT&CK technique.
- **What this check could not see** is always listed: not administrator, a part that could not be read, live-only limits.
- Leads are leads. A match is not proof of compromise and an empty result is not proof of a clean machine.

### Tuning

All patterns are in `config\profiles\live_indicators.json` (regular expressions, severities, texts). Add your organisation's tools to `Tools`, or remove a pattern that is normal on your estate. AS4 never flags its own process tree.

## Live Watch

Polls every 2 seconds (no event subscriptions, drivers or installs) for a time you choose, and records new processes with their parent and command line, programs that end, new internet connections, new listeners and new DNS lookups. Each new process goes through the same rules as Live Hunt. A connection that comes back at a steady rhythm to the same address, or an address that keeps refusing, is flagged as a possible beacon. Programs that start and end between two polls are missed; the event logs and Prefetch cover that.

## Snapshots

A snapshot stores the programs, services, drivers, scheduled tasks, autostarts, startup files, WMI subscriptions, listening ports, internet peers, local users, administrators, installed software and hosts entries.

Use it three ways: before and after a suspicious action; at the start and end of an incident; or against a snapshot taken on a clean reference machine of the same build. The comparison lists what was **added, removed or changed**, with script-host paths and attack-tool names called out first.

## First Response

Pick the situation; AS4 picks the collection and runs it in order of volatility: snapshot, live state, Live Hunt, files, event logs, report.

| Scenario | For |
|---|---|
| First 5 minutes | You just arrived. Volatile data, a snapshot and the Live Hunt. |
| Suspected malware | Unknown program or an alert. Processes, services, tasks, autostarts, Prefetch, Amcache, Shimcache, Defender history, relevant logs. |
| Suspicious logons or RDP | Sessions, accounts, RDP traces, logon/RDP/remote-access logs. |
| Ransomware | State, shares, recent dropped files, logs. Capture memory first if the machine is still on. |
| Data theft or user activity | Recent files, USB/share traces, browser history, deleted files, user activity. Holds private data: use only with authority. |
| Persistence sweep | Every autostart place, scored. |
| Full triage | All live checks and artifacts that are safe to collect live. |

Items that need administrator are skipped and reported as `SKIPPED` when AS4 is not elevated. Private-data items can be switched off with one tick.

CLI: `AS4_IR_Tool_CLI.exe -Batch malware -Case "Name"` (also `first5`, `logons`, `ransomware`, `insider`, `persistence`) or `-Batch hunt`.

## Limits

- It is a live view of one moment. Code that lives only in memory, or hides from Windows itself, can be invisible: capture memory when in doubt.
- Without administrator the Security log, Prefetch, Defender exclusions and other users' process paths are not visible. The report says so.
- Signature status comes from Windows' own verifier on that machine. Windows may contact certificate authorities for revocation data when the machine is online; disconnect the network first if you need zero traffic.
- Tested on Windows 10/11 (64-bit). Older Windows, 32-bit and ARM are untested; see `docs\COMPATIBILITY.md`.

## How light is it?
Everything runs at below-normal priority. Measured on a 64-bit Windows 11 workstation (standard user): a full Live Hunt takes about 30 s wall time and about 16 s of CPU time spread over that period (roughly half of one core at low priority); gentle mode takes about 13 s and 9 s. Live Watch is one process query every 3 seconds.

**Gentle mode** switches on by itself on Windows Server and when the CPU is above 75%, or by tick box / `AS4_GENTLE=1`: pauses between checks, no scan of recently dropped files, no signature checks of programs in Program Files and Windows, smaller event log reads, Live Watch every 5 seconds. Hayabusa runs with half of the cores. Nothing is ever written to the machine's disk outside the AS4 folder.
