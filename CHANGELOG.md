# Changelog

## 1.1.0

New: live analysis and faster collection.

- **Live Hunt**: reads the running machine and scores what stands out (core Windows processes in the wrong folder or with the wrong parent, imitation names, Office or web servers starting shells, encoded and download commands, unsigned programs in temp folders, odd connections, services and drivers, ~20 persistence places, accounts, Defender and firewall state, event logs, recently dropped files, attack-tool names, Cobalt Strike style named pipes). Writes an HTML report with a process tree, a verdict in plain words, next steps and an honest list of what it could not see.
- **Live Watch**: records what starts, connects and resolves for a chosen time; flags steady reconnects that look like beacons.
- **Snapshots**: save the machine state and compare two snapshots (or one from a clean reference machine) to see what was added, removed or changed.
- **First Response**: seven situations (first 5 minutes, malware, suspicious logons/RDP, ransomware, data theft, persistence sweep, full triage) that pick the right collection, in order of volatility, and finish with a report.
- **Self-exclusion**: scans describe the machine, not AS4. Detections caused by AS4 itself (its own commands, scripts, exports, rule files, bundled tools in Prefetch, Defender hits inside its folder) are left out of Quick Scan, Hayabusa findings, Live Hunt and Live Watch, and each report says how many were left out. Raw timelines are untouched. Rules: `config/profiles/self_exclusions.json`.
- Editable rule file: `config/profiles/live_indicators.json`.
- GUI pages: First Response, Live Hunt. CLI menus 14-15. Batch modes `hunt` and one per scenario.

## 1.0.0

First public version: Quick Response, event logs, artifacts, persistence triage, Hayabusa (21 ready-made questions), Chainsaw, KAPE, FTK Imager workflows, WinPmem, Volatility, YARA, IOC search, timeline, Quick Scan, hash ledger with sealed runs, HTML/CSV/JSON reports, portable exe launchers.
