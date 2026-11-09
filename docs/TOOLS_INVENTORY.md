# Tools inventory

Checked 2026-10-17 on the analyst workstation (Windows 11 Pro 26200, AMD64). "Bundled" means the files are in `tools\` and their hashes match `config\tools_manifest.json`. Live status: `AS4_IR_Tool_CLI.exe -Check` or the Tools page.

| Tool | Version | Location | Signature | Ran here |
|---|---|---|---|---|
| KAPE and gkape | 1.3.0.2 | `tools\KAPE\` (267 targets, 288 modules) | valid (Eric Zimmerman) | `kape.exe --help` yes; collection not run |
| FTK Imager | 3.4.3.3 (64-bit) | `tools\DiskForensics\FTK Imager\` (plus `mfc100u`, `mfcm100u`, `msvcr100`, `msvcp100` from `tools\_runtime`; the copy that was added lacked them and stopped with a system error on clean machines) | valid (AccessData) | Its libraries load from its own folder; the program itself was not started (it requires elevation) |
| Hayabusa | 4.2.0 (Autumn Release), win-x64 | `tools\Hayabusa\` (exe, `rules` about 5,000 files, `config`) | not signed | Yes, all commands and options |
| Chainsaw | 2.17.1 | `tools\Chainsaw\chainsaw\` (exe, `rules`, `sigma` 3,155 files, `mappings`) | not signed | Yes (hunt and search) |
| YARA | 4.5.5 | `tools\YARA\` | not signed | Yes |
| YARA community rules | 534 files | `config\rules\yara\community\` | n/a | All 534 compile |
| Volatility 3 | 2.28.2 | `tools\Volatility3\` | not signed | Yes |
| WinPmem | 4.0 rc2 mini x64 (and go-winpmem 1.0 rc2) | `tools\MemoryAcquisition\` | mini valid (Velocidex); go not signed | Help only; capture needs admin |
| Belkasoft RAM Capturer | n/a | `tools\MemoryAcquisition\RamCapturer\` | see manifest | Not run (GUI, admin) |
| Sysinternals | Autoruns 14.3, Sigcheck 2.93, Handle 5.0, ListDLLs 3.3, PsTools 1.41, TCPView 4.19, Strings 2.54, plus the rest of the suite | `tools\Sysinternals\` | valid (Microsoft) | Autoruns and Sigcheck yes |
| NetworkMiner 2.7.3, LastActivityView, ShadowCopyView, RegScanner, DNSQuerySniffer, ExifTool 11.29, Arsenal Image Mounter 3.9.239 | as listed | `tools\Other\` | see manifest | Not run (GUI tools; launch from the Tools page) |
| Volatility Windows symbols | - | `tools\Volatility3\symbols\windows.zip` | - | Not downloaded (800 MB; too slow here) |

Free tools were downloaded from the official project or vendor URLs listed in `scripts\Get-Tools.ps1`. KAPE, FTK Imager and the extra tools were supplied by the maintainer and are not redistributable; see LICENSES.md. Vendors do not publish checksums for these assets, so the recorded SHA-256 values prove integrity from now on, not against the vendor.

## Notes from the clean-up
- From the KAPE copy that was added, these were removed two console logs, a `Modules2026...` folder (the output of an earlier module run, about 26,700 files), the update script `Get-KAPEUpdate.ps1` (it downloads from the internet) and `gkape.settings` (it held a path from your earlier run).
- Hayabusa: only the Windows x64 build, `rules` and `config` were kept from the all-platforms zip (Linux, macOS, ARM and x86 builds removed). The zip's SHA-256 is recorded in the manifest. `update-rules` (downloads), `set-default-profile` and `level-tuning` (change the tool's own files) are not offered by AS4; update rules on the analyst workstation by replacing `tools\Hayabusa\rules`.
- Not kept from `more tool`: duplicates of KAPE, FTK Imager and the Sysinternals suite (the missing Sysinternals files were merged in), Sysmon (installing it changes the target), RedLine, Regshot, Forensicator.ps1, Base64.ps1, avml (Linux), apatedns and the APK reverse-engineering archive. The SANS Windows forensics poster was copied to `docs\`.
- Extraction note: 7 Sigma `regression_data` fixture files in the Chainsaw archive were refused when extracted (probably antivirus). They are test fixtures, not rules.

## By dependency
- Administrator: Security log, Prefetch, Amcache, SRUM, WMI repository, registry hive save, Defender history, Recycle Bin, NTFS and USN via fsutil, KAPE live collection, memory capture, FTK Imager.
- Nothing extra: Quick Response, persistence triage, event logs, artifacts, IOC search, timeline, integrity, reports.