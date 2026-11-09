# Evidence Handling

## Output structure
`output\<case name>\` contains `00_Metadata` (case.json, `hashes.csv` ledger, `seal_<run>.sha256`), `01_System_Info`, `02_Network`, `03_Processes_Services`, `04_Users_Authentication`, `05_Event_Logs` (`raw_evtx\` originals, `filtered_evtx\` derived), `06_KAPE`, `07_Memory`, `08_Disk`, `09_Persistence`, `10_Artifacts`, `11_Hayabusa_Analysis`, `11_Chainsaw_Analysis`, `12_Reports`, `13_Collection_Logs` (`manifest.jsonl`, `session.log`), `14_Live_Analysis` (Live Hunt, Live Watch and snapshot files). Folders are created only when used.

## Recorded for every operation (`manifest.jsonl`, one JSON per line)
Run ID, task ID/name, status (`OK`, `FAILED`, `SKIPPED`, `TIMEOUT`, `CANCELLED`), start/end UTC, exit code, command and exact arguments, tool version, source, destination files, SHA-256 of each file, notes and warnings. Status is derived from exit code and output, never from "a file exists".

## Integrity
- `hashes.csv` lists SHA-256 of every file AS4 wrote (kind `raw` = collected; `derived` = analysis output).
- At the end of each run `seal_<run>.sha256` hashes the manifest, ledger and case.json, so later edits are detectable.
- Verify any time: GUI Report and Integrity > Verify hashes, CLI option 11. Reports `OK / MISMATCH / MISSING` and writes `12_Reports\integrity_verification_*.csv`.
- AS4 never overwrites: new runs get new timestamped file names; creating an existing case ID is refused; the writer refuses existing paths.

## Raw vs derived
Original EVTX, copied artifacts, tool stdout are raw evidence. Filtered EVTX, Chainsaw/YARA/IOC output, timelines and reports are derived and kept in separate folders/labelled in the manifest.

## Timestamps
Copied files get the source Created/Modified/Accessed times applied; originals are also listed in each `_inventory.csv`. Limits: reading may change last-access time on the source if NTFS last-access updating is enabled; ACLs/streams are not preserved; copying creates new file-system records. Timeline rows without an explicit zone are labelled `UNCERTAIN` (assumed analysis-host local time) - confirm the target time zone from the `datetime` task.

## Live-response limitations (state them in your report)
- Running any command creates processes, may add Prefetch entries, event log records (e.g. 4688), and changes memory contents. Reading files can alter access times.
- Memory acquisition loads code/drivers, is not zero-impact, can fail on protected systems, and the image contains credentials, tokens and personal data. Store only on the evidence drive; protect and hash it. Free space is checked first; success requires exit code 0 **and** a plausible image file.
- Volatile data (connections, DNS cache, processes) is collected first in the Quick set because it is the most perishable; order within a run follows the task list.
- Locked hives/databases are read with shared access when possible; failures are recorded. Raw `$MFT`, `$LogFile`, `$J` need raw volume access - use KAPE/FTK Imager or image the disk.
- Sensitive content: SAM/SECURITY hives (copied, never parsed), browser history, PowerShell history, memory. Collect only with authority. AS4 does **not** extract credentials and does not copy browser logins/cookies.
- Nothing is uploaded; AS4 itself makes no network connections. (The signature check uses Windows' own verifier, which may contact certificate authorities for revocation data if the machine is online. Disconnect the network first if you need zero traffic.) AS4 does not delete, kill, quarantine, clear logs, or change audit settings.
- `autorunsc -accepteula` (if you bundle Autoruns) writes a registry value on the target.

## Live analysis files
`hunt_inventory_*.json` and `snapshot_*.json` are raw (what the machine looked like); `hunt_findings_*`, `LiveHunt_*`, `LiveWatch_*` and `snapshot_changes_*` are derived (what AS4 concluded). `watch_events_*` is raw observation. All are in the hash ledger.

## Findings language
Heuristic `TriageLeads`, Chainsaw/Sigma matches, YARA and IOC hits are leads for analyst review - not confirmed compromise.
