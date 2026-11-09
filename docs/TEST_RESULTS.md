# Test results

Run on 2026-11-03 on the analyst workstation (Windows 11 Pro 26200, AMD64, PowerShell 5.1), standard user (not elevated), against a copy of AS4 mapped to drive `Z:` (path with spaces), using synthetic data, exported local event logs and throw-away cases. Driver: `scripts\Test-AS4.ps1`.

**67 tests: 64 passed, 0 failed, 3 blocked.** Blocked means it could not be tested here; it is not a pass.

## Quick Scan (new, optional)
- Scoring on synthetic rows: cleared log, Mimikatz-style rule, new service and 12 failed logons followed by a success from the same address produce "Serious indicators" with the reasons listed; no rows produce "No rule matched" (QS01). The separator between MITRE tactics is split correctly.
- Log discovery: a case with duplicate copies of the same logs (raw export, KAPE copy, filtered copy, AS4's own output) scans each distinct log once (QS02).
- Blind spots: missing log types are listed; a Security log that starts weeks after the System log is flagged as possibly cleared (QS03).
- Real run on exported PowerShell and Application logs: verdict "Needs attention", HTML and text summaries saved and hashed, no external URLs in the summary, fast mode never finds more than full mode, Chainsaw second opinion completes (QS04). A scan of about 25 MB of logs took 15 seconds including the second opinion.
- The result page was driven end to end in the GUI and checked in a screenshot. A bug found there (a colour argument passed as text) was fixed.
- Not tested: Security, RDP and Sysmon logs from a real incident (none available here), so the logon and brute-force logic is validated on synthetic rows only.

## Gentleness (new)
Child tools run at below-normal priority and Hayabusa uses half of the CPU cores unless the analyst sets a number (QS05). Older Windows, 32-bit and ARM were **not** tested; see `COMPATIBILITY.md`.

## Earlier results that still hold
Hayabusa: 12 commands parsed, 188 option runs accepted, 21 scenarios run on real logs; Chainsaw 2.17.1 hunt and search; KAPE 267 targets and 288 modules discovered; 534 YARA rules compile; unattended batch 28 OK and 1 FAILED (`query user`).

## Not tested
WinPmem capture (M02), KAPE and FTK Imager launch or live collection, Volatility on a real dump (V02, none fabricated), Hayabusa live analysis, Security log and RDP findings on real data, elevated runs, real USB, Windows 7/8.1/Server 2008-2012, Windows 10 and Server, 32-bit.

## Launcher executables and release package
- The three launcher exes build with the C# compiler that ships with Windows (`scripts\Build-Exe.ps1`). Their logic was tested by loading the built assembly and running its entry point: it found the AS4 folder, started Windows PowerShell with the right arguments and returned the exit code of `-Check`. The exes carry product and version information and no user name, build path or tool names.
- **Running the exe files directly was blocked on this workstation** by Windows application control, because they are unsigned. This is expected on machines with Smart App Control or WDAC; use `scripts\Start-Without-Exe.cmd` or sign the exes (`scripts\Build-Exe.ps1 -SignThumbprint`). The exes were therefore not run as normal programs here.
- `scripts\New-Release.ps1` builds `dist\AS4_IR_Tool_<version>.zip` (about 135 MB, 9,524 files, standard forward-slash entry names) plus `SHA256SUMS.txt`. It refuses to build if the package contains KAPE, FTK Imager, Sysinternals, Volatility, Belkasoft, NirSoft or Arsenal files, PDFs, case data, or personal data. The build checks that the archive holds every staged file. The package was extracted to a new folder with a space in its path and tested there: Hayabusa, Chainsaw, WinPmem and YARA verified against their hashes; the full self-test gave 54 passed, 0 failed and 9 blocked (the blocked ones need tools that are not in the public package: KAPE, FTK Imager, Volatility, Autoruns and the community YARA rules); the GUI built all 15 pages; the launcher logic returned exit code 0.

## Runtime libraries (new)
- Cause of the reported FTK Imager error ("mfc100u.dll was not found"): the FTK Imager folder that was added did not contain the Visual C++ 2010 MFC runtime, and the machine did not have it installed either. Reproduced here: loading FTK's `adencrypt.dll` with only its own folder and System32 on the search path failed with Windows error 126 before the fix and loaded after it.
- Fix: the four needed DLLs (`mfc100u`, `mfcm100u`, `msvcr100`, `msvcp100`) were unpacked from Microsoft's own Visual C++ 2010 SP1 installer (nothing installed) and placed next to FTK Imager. Chainsaw and YARA need `vcruntime140.dll`, which many clean machines also lack; the Visual C++ 2015-2022 DLLs were unpacked from Microsoft's installer the same way.
- Prevention: `tools\_runtime\x64` holds the DLLs; AS4 reads each program's import table and copies any missing runtime DLL next to it the first time the program is used, and `-Check` does this for every tool. Tests: PE reader (RT01), repair of a program copied to a bare folder (RT02), FTK libraries load without the installed redistributable (RT03), Chainsaw and YARA (RT04).
- Limits: the FTK Imager program itself was not started (it needs elevation); .NET programs (KAPE, gkape, Arsenal Image Mounter) cannot be fixed this way.

## Detailed results| ID | Result | Test | Detail |
|---|---|---|---|
| C01 | **PASS** | Case name creates output\<name>; existing case resumes; bad names refused |  |
| C02 | **PASS** | Evidence writer refuses to overwrite existing file |  |
| C03 | **PASS** | Argument quoting handles spaces, quotes, trailing backslash |  |
| N01 | **PASS** | Native command OK: stdout, exit code, hash, manifest |  |
| N02 | **PASS** | Command failure is FAILED with real exit code (file existing is not success) |  |
| N03 | **PASS** | stderr captured separately |  |
| N04 | **PASS** | Timeout kills process and reports TIMEOUT |  |
| N05 | **PASS** | Missing command is SKIPPED, not a crash |  |
| N06 | **PASS** | Admin-required task is SKIPPED when not elevated (or runs when elevated) |  |
| N07 | **PASS** | One failing task does not stop the batch |  |
| N08 | **PASS** | Cancellation: remaining tasks CANCELLED, completed evidence still verifies |  |
| N09 | **PASS** | PowerShell-based task emits CSV+JSON+TXT |  |
| N10 | **PASS** | Structured network connections (CSV) has process names |  |
| N11 | **PASS** | Triage tasks (runkeys, services, wmi, tasks, startup) run without crashing |  |
| E01 | **PASS** | Event log export (Application) produces non-empty EVTX in raw_evtx |  |
| E02 | **PASS** | Missing channel -> SKIPPED; Security without admin -> SKIPPED |  |
| E03 | **PASS** | Filtered export is labelled derived and goes to filtered_evtx |  |
| E04 | **PASS** | Channel metadata (wevtutil gli) saved |  |
| A01 | **PASS** | Folder collection: filters, relative paths, hashes, timestamps, duplicates |  |
| A02 | **PASS** | Missing artifacts are recorded, not fatal (non-admin categories) |  |
| A03 | **PASS** | Raw $MFT/$LogFile/$J are NOT claimed as collected |  |
| I01 | **PASS** | IOC search finds IP/domain(case-insens)/hash; binary files listed as skipped |  |
| I02 | **PASS** | Timeline: explicit-UTC rows high confidence, zone-less rows flagged UNCERTAIN |  |
| R01 | **PASS** | Hash ledger verifies; tampering and deletion are detected |  |
| R02 | **PASS** | Run seal files exist |  |
| R03 | **PASS** | Report matches manifest counts and avoids compromise claims |  |
| H01 | **PASS** | Chainsaw detected and registered/verified against manifest hash | status=PRESENT_VERIFIED |
| H02 | **PASS** | Chainsaw executes on this host (version + real help) | version=chainsaw 2.17.1 |
| H03 | **PASS** | Chainsaw hunt on EVTX using real binary |  |
| H04 | **BLOCKED** | Chainsaw runner reports SKIPPED with reason when binary blocked/missing (never reports a success it did not get) | BLOCKED: only applicable when the binary cannot run |
| H05 | **PASS** | Chainsaw arg builder only emits flags present in help (synthetic help text, NOT the real binary) |  |
| H06 | **PASS** | Chainsaw result loader parses CSV/JSON (synthetic sample) |  |
| K01 | **PASS** | KAPE is detected with its real Targets and Modules | KAPE 1.3.0.2: targets=267 modules=288 |
| K02 | **PASS** | KAPE run is SKIPPED without administrator and refuses unknown targets |  |
| K03 | **PASS** | Every target and module named in the KAPE scenario profiles exists in the bundled KAPE |  |
| M01 | **PASS** | WinPmem is SKIPPED without administrator (never auto-runs when elevated); space check works |  |
| M02 | **BLOCKED** | Real memory acquisition with WinPmem | BLOCKED: needs an elevated session and an analyst decision (intrusive); not auto-run |
| M03 | **PASS** | FTK Imager: Register output hashes a synthetic .mem and rejects an empty disk folder; FTK GUI launch is manual (UAC) | BLOCKED (launch only): FTK Imager is bundled; opening it needs a UAC prompt, so it is a manual test |
| Y01 | **PASS** | YARA scan with the bundled yara64.exe finds a synthetic match |  |
| Y03 | **PASS** | Bundled community YARA rule set (534 files) compiles into an index | compiled 534 of 534, skipped 0 |
| Y02 | **PASS** | YARA with a rule folder: compiles each rule, skips broken ones, scans |  |
| V01 | **PASS** | Volatility on a non-dump file reports FAILED, never OK |  |
| V02 | **BLOCKED** | Volatility on a real memory dump | BLOCKED: no real memory dump available on this workstation (none available) |
| A04 | **PASS** | Autoruns (autorunsc64) runs and returns rows |  |
| T01 | **PASS** | Downloaded tools are registered and verified against recorded hashes |  |
| HB01 | **PASS** | Hayabusa detected, runs, version and rules present, hash verified | Hayabusa v4.2.0 - Autumn Release, 5000 rule files |
| HB02 | **PASS** | Option parser: every option in each command help is parsed (no option lost) | all 12 commands parsed |
| HB03 | **PASS** | dfir-timeline on a real exported EVTX: CSV with header, HTML report, arguments recorded, hashes ledgered |  |
| HB04 | **PASS** | Bad input is refused before running (level, missing input, search without pattern, unknown option warned) |  |
| HB05 | **PASS** | search, logon-summary, eid-metrics, computer-metrics, log-metrics, extract-base64, pivot-keywords-list, sort-csv run OK |  |
| HB06 | **PASS** | All Hayabusa presets build valid command lines | 10 presets |
| HB07 | **PASS** | Every option and filter of every command is accepted by the Hayabusa binary (executed one by one on a tiny EVTX) | 188 option runs, all accepted (--geo-ip needs a MaxMind database and --json-input needs JSON logs: built, not executed) |
| HS01 | **PASS** | Scenario file: 21 scenarios, unique ids, valid commands, every option exists in that command, event IDs are numeric | 21 scenarios |
| HS02 | **PASS** | Multi-value options are sent as one comma-separated value; simple choices become real options |  |
| HS03 | **PASS** | Log hints: a scenario warns when the needed log type is not in the folder |  |
| HS04 | **PASS** | All 21 scenarios run on real exported logs; none fails; PowerShell scenario finds events; scenario filter writes findings_filtered.csv | powershell=523 serious=18 all_rules=554 |
| QS01 | **PASS** | Quick Scan scoring on synthetic rows: cleared log + credential theft + service + password guessing that succeeded -> serious; no rows -> "No rule matched" |  |
| QS02 | **PASS** | Quick Scan finds log folders in a case, skips AS4 output and filtered copies, and does not scan the same logs twice |  |
| QS03 | **PASS** | Quick Scan coverage: missing log types become blind spots; Security log starting much later than System is flagged |  |
| QS04 | **PASS** | Quick Scan on real exported logs: verdict, HTML and text summary saved and hashed, no external URLs, fast mode finds no more than full mode, Chainsaw second opinion | verdict=Needs attention score=36 total=554 fast=491 |
| QS05 | **PASS** | Gentle on the endpoint: child tools run at BelowNormal priority and Hayabusa is limited to half the cores |  |
| RT01 | **PASS** | PE reader: machine type and imported DLLs of a real program (no execution) |  |
| RT02 | **PASS** | Self-repair: a program copied to a folder without its Visual C++ runtime gets the DLL from tools\_runtime |  |
| RT03 | **PASS** | FTK Imager libraries load using only their own folder and System32 (works without the Visual C++ 2010 redistributable installed) |  |
| RT04 | **PASS** | Chainsaw and YARA have vcruntime140.dll beside them after repair |  |
| S01 | **PASS** | No download/install/remediation primitives in application code |  |
| S02 | **PASS** | Application contains no hardcoded drive-letter roots (except C:\ Windows artifact locations) |  |

PASS=64 FAIL=0 BLOCKED=3

## Live analysis, First Response, evidence package, self-exclusion (1.1.0)
Self-test suite on a copy of the folder (path with spaces), standard user, Windows 11 Pro build 26200: 74 pass, 0 fail, 3 blocked (needs a real memory dump or an elevated session).
- LH01-LH04: inventory, process rules on synthetic processes, verdict scale, end-to-end Live Hunt (files hashed as raw/derived, report without external links, AS4 does not flag itself).
- LW01: Live Watch sees a program started outside AS4. SN01: snapshot compare finds added, removed and changed items.
- SC01-SC02: every scenario resolves; First Response runs in order and ends with the Live Hunt and a case report.
- PK01: evidence package, checksum list, verify passes and detects tampering.
- SE01: AS4's own footprint is left out of Quick Scan, Hayabusa findings and Live Hunt; ordinary activity is kept.
- Footprint check: during a First Response run and a package build, no file was created or changed in Temp, AppData, LocalAppData, ProgramData or Windows\Temp.
Not tested: administrator runs, Windows 7/8/Server, 32-bit and ARM, the launcher exes (blocked here by Smart App Control), a real infected machine.
