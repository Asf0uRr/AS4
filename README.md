# AS4 IR Tool

A portable incident-response and live-triage toolkit for Windows. Copy the folder to a USB drive, run it on the machine you need to look at, and get evidence plus a plain-language answer to *"is something wrong here, and what do I do next?"*

- **Runs from its own folder.** Any drive, any path (spaces are fine). Nothing is installed on the endpoint.
- **Read-only.** It does not delete, stop, quarantine, clear logs, extract credentials or change settings. It makes no network connections of its own.
- **Local.** Detection rules and tools ship with it. Nothing is downloaded or uploaded.
- **GUI and CLI.** Windows PowerShell 5.1 and WinForms only (both part of Windows).
- **Evidence you can defend.** One folder per case, a SHA-256 ledger, sealed runs, a manifest of every command, and a chain-of-custody package.

## What it does

| | |
|---|---|
| **Collect evidence** | **First Response** picks the right collection for the situation (first 5 minutes, malware, suspicious logons/RDP, ransomware, data theft, persistence sweep, full triage) and runs it in order of volatility. Also: 38 live-response commands, 22 artifact groups (Prefetch, Amcache, Shimcache, jump lists, browser history, SRUM, WMI, registry hives...), event log export, memory and disk imaging workflows (FTK Imager, WinPmem), KAPE |
| **Live analysis** | **Live Hunt** scores the running machine in about 30 seconds: process impersonation and wrong parents, Office or web servers spawning shells, encoded and download commands, LSASS dumping, unsigned programs in temp folders, odd connections, ~20 persistence places, accounts, Defender and firewall state, event logs, recently dropped files, attack-tool names, Cobalt Strike pipes. **Live Watch** records what starts, connects and resolves, and flags beacon-like reconnects. **Snapshots** show exactly what changed between two moments or against a clean reference machine |
| **Analyze** | Quick Scan (point it at any folder of logs, get a verdict, attack chain and incident window), Hayabusa with 21 ready-made questions, Chainsaw (Sigma), YARA, IOC search, UTC timeline |
| **Hand over** | Examiner notes, HTML/CSV/JSON reports, and an **evidence package**: one zip with a chain-of-custody record, a checksum list for every file and a verify function that detects tampering |

Every finding says what was seen, why it matters and what to do next. Verdicts are leads for a person to confirm, never proof, and every report lists **what the check could not see**.

## Start

1. Get the release package (or clone this repository and run `scripts\Get-Tools.ps1` on an analyst workstation to fetch the free tools). Copy the folder to your drive.
2. On the endpoint, start one of:

| Action | How |
|---|---|
| GUI | `AS4_IR_Tool.exe` |
| GUI as administrator | `AS4_IR_Tool_Admin.exe` (administrator shows more: Security log, Prefetch, all process paths, memory capture) |
| Command line menus | `AS4_IR_Tool_CLI.exe` |
| Environment and tool check | `AS4_IR_Tool_CLI.exe -Check` |
| Unattended | `AS4_IR_Tool_CLI.exe -Batch hunt -Case "Name"` (also `quick`, `triage`, `evtx`, `first5`, `malware`, `logons`, `ransomware`, `insider`, `persistence`, `package`) |
| No exe files | `scripts\Start-Without-Exe.cmd` takes the same arguments (use it if a policy blocks unsigned exe files) |

3. Type a case name. A folder `output\<case name>\` is created (or reopened) and everything goes inside it. Nothing already there is overwritten.
4. Open **First Response**, choose the situation, press *Run this*. Read the Live Hunt report. Build the **Evidence Package** when you are done.

The exe files are small launchers for `app\Main.ps1`. They are **not code-signed** (see `docs\TROUBLESHOOTING.md`); you can sign them with your own certificate using `scripts\Build-Exe.ps1 -SignThumbprint`.

## Layout

```
AS4\
  AS4_IR_Tool.exe, AS4_IR_Tool_Admin.exe, AS4_IR_Tool_CLI.exe
  app\       Main, Core (engine), Cli, Gui, GuiLive, CliLive
  tasks\     one file per job: QuickResponse, Persistence, EventLogs, Artifacts, Hayabusa, Chainsaw, Kape,
             Memory, Yara, IocSearch, Timeline, Integrity, Report,
             LiveHunt, LiveReport, LiveWatch, Scenarios, Package
  tools\     third-party programs (see tools\README.md); every one is optional
  config\    tools.json, profiles\ (Hayabusa, Chainsaw, KAPE presets, live_indicators.json,
             scenarios_collect.json, triage scoring), rules\
  output\    one folder per case, plus _packages\
  scripts\   Get-Tools, Prepare-Tools, Test-AS4, Build-Exe, New-Release
  docs\
```

Case folder: `00_Metadata  01_System_Info  02_Network  03_Processes_Services  04_Users_Authentication  05_Event_Logs  06_KAPE  07_Memory  08_Disk  09_Persistence  10_Artifacts  11_Hayabusa_Analysis  11_Chainsaw_Analysis  12_Reports  13_Collection_Logs  14_Live_Analysis` (created only when used).

## Customise

- Detections are data: edit `config\profiles\live_indicators.json` (command-line patterns, attack-tool names, named pipes, expected system processes).
- Situations are data: edit `config\profiles\scenarios_collect.json`.
- Add a third-party tool: put it under `tools\`, add an entry to `config\tools.json`, register its hash with `scripts\Prepare-Tools.ps1 -Register`.

## On infected or evidence machines

- Run it **from a USB drive**, not from the machine's own disk, and keep `output\` on that drive. AS4 writes only inside its own folder (cases in `output\`, packages in `output\_packages\`); its temporary files stay in `output\_work`. A test that watched Temp, AppData, LocalAppData, ProgramData and Windows\Temp during a First Response run plus a package build found no file created or changed there.
- Everything it needs is in the folder, including the Visual C++ runtime DLLs. It downloads and installs nothing.
- Unavoidable traces: Windows itself records that programs ran (Prefetch, event logs, UserAssist) and PowerShell keeps its usual caches. The one optional item that writes to the registry is Autoruns (`-accepteula`); it is off by default and the CLI warns before running it.
- Running as administrator (`AS4_IR_Tool_Admin.exe`) shows more; without it AS4 says what it could not see.

## Honest limits

Running any program changes a live system (new processes, Prefetch entries, event log records); memory capture is not zero-impact. Without administrator, the Security log, Prefetch, Defender exclusions and other users' process paths are invisible, and the report says so. A live view cannot see code that lives only in memory or hides from Windows: capture memory when in doubt. Tested on Windows 10 and 11 (64-bit); older Windows, 32-bit and ARM are untested. See `docs\EVIDENCE_HANDLING.md`, `docs\COMPATIBILITY.md` and `docs\TEST_RESULTS.md`.

## Documentation

`docs\QUICK_START.md` · `docs\LIVE_ANALYSIS.md` · `docs\EVIDENCE_HANDLING.md` · `docs\TOOLS_INVENTORY.md` · `docs\COMPATIBILITY.md` · `docs\TROUBLESHOOTING.md` · `docs\PORTABILITY.md` · `docs\LICENSES.md`

## Build and test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Test-AS4.ps1   # self-test on synthetic data
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Build-Exe.ps1  # launcher exes
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\New-Release.ps1 # dist\AS4_IR_Tool_<version>.zip + SHA256SUMS.txt
```

The release package contains only components whose licences allow redistribution (Hayabusa, Chainsaw, YARA, WinPmem, Microsoft Visual C++ runtime DLLs) and none of your cases.

## Licence

AS4 IR Tool code: MIT (`LICENSE`). Bundled third-party programs keep their own licences: `docs\LICENSES.md`, `docs\THIRD_PARTY_NOTICES.md`.

Use it only on systems you are authorised to examine.
