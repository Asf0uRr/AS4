# Quick Start

## Prepare the USB (analyst workstation)
1. Copy the `AS4` folder to the USB drive (use NTFS or exFAT; FAT32 cannot hold memory images over 4 GB).
2. KAPE, FTK Imager, YARA, Volatility, WinPmem and the Sysinternals tools are already in `tools\`. To add more, put them under `tools\`, add them to `config\tools.json` and run `scripts\Prepare-Tools.ps1 -Register -Tool <id> -File <exe>`.
3. For offline Windows memory analysis, run `scripts\Get-Tools.ps1` on a fast connection to add the Volatility symbol pack (800 MB).
4. `AS4_IR_Tool_CLI.exe -Check` shows what is present.

## On the endpoint
1. Start `AS4_IR_Tool_Admin.exe` (administrator is needed for the Security log, Prefetch, hives, memory and KAPE).
2. Type a case name. A folder with that name is created in `output\` and everything goes inside it.
3. Work through the pages on the left. **Not sure where to start? Open First Response**, pick the situation and press *Run this*; then read the Live Hunt report. Pages:
   - **First Response**: seven situations (first 5 minutes, malware, logons/RDP, ransomware, data theft, persistence, full). AS4 picks what to collect and in which order.
   - **Live Hunt** (Analyze group): *Run Live Hunt* gives a verdict for this machine in about 30 seconds; *Live Watch* records what starts and connects; *Take snapshot* and *Compare* show what changed.
   - **Evidence Package** (Case group): write notes, build the zip with the chain-of-custody record, verify a package.
   - **Quick Response**: one button per command, or Run quick set.
   - **Event Logs**: tick channels, optional event IDs and UTC time range, Export.
   - **Artifacts**: tick categories (details are shown for each), optional date, extension and size filters.
   - **Persistence**: processes with hashes and signatures, services, tasks, Run keys, WMI, recent files.
   - **Memory**: Open FTK Imager, then File > Capture Memory, paste the destination (already in the clipboard), capture, then Register output. WinPmem is available as an alternative.
   - **Disk Image**: Open FTK Imager, File > Create Disk Image, destination = the case folder, then Register output.
   - **Quick Scan (optional)**: a fast answer to *is anything wrong?* Choose where the logs are (everything in this case, another folder, one file, or this computer), press Scan now. It runs the Hayabusa rules and shows a verdict with the reasons, the attack chain by MITRE tactic, the incident window, the most involved hosts, accounts and addresses, **blind spots** (log types missing, cleared or short logs) and next steps. Optional checkboxes: fast mode and a Chainsaw second opinion. The summary is saved as HTML and text in 12_Reports. Run it on the case after exporting logs or after a KAPE collection.
   - **Hayabusa**: answer three questions (which logs, when, how serious), tick what you want to find (for example Remote Desktop (RDP) activity, Failed logons, PowerShell activity, Persistence, Accounts created, Logs cleared) and press Run selected. The findings appear in one table, coloured by severity, with a search box and severity filter. A timeline CSV, an HTML report and the raw output are saved in 11_Hayabusa_Analysis. If no logs were exported yet, it offers to export them. **Hayabusa Advanced** has every command, option and filter.
   - **Chainsaw / KAPE / IOC, YARA, Timeline**: analysis and collection with the other bundled tools.
   - **Report and Integrity**: Verify hashes, Create report.
4. Take the whole `output\<case name>\` folder with you, or build an evidence package and take `output\_packages\`.

## Command line
`AS4_IR_Tool_CLI.exe`: type the case name, then pick numbers (`1,3,5-8`), `Q` for the quick set, `A` for all, `B` to go back, `C` to change case, `H` for help. Quick Scan is option 7, Hayabusa is option 8: pick questions by number, then answer which logs, when and how serious. V opens the advanced options (P preset, C command, I input, O all options, V show command, R run).
