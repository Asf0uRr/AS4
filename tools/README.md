# tools

Third-party programs AS4 can drive. None of them are part of this repository; each keeps its own licence (see `docs/LICENSES.md`).

| Folder | Program | How to get it |
|---|---|---|
| `Hayabusa\` | Hayabusa (Sigma-based event log timeline and detections) | `scripts\Get-Tools.ps1` |
| `Chainsaw\` | Chainsaw with Sigma rules | `scripts\Get-Tools.ps1` |
| `YARA\` | YARA | `scripts\Get-Tools.ps1` |
| `MemoryAcquisition\` | WinPmem | `scripts\Get-Tools.ps1` |
| `Sysinternals\` | Autoruns, Sigcheck, Handle, ListDLLs, PsTools, TCPView, Strings | `scripts\Get-Tools.ps1` |
| `Volatility3\` | Volatility 3 | `scripts\Get-Tools.ps1` |
| `KAPE\` | KAPE | Kroll registration form (not redistributable); then `scripts\Prepare-Tools.ps1 -Register` |
| `DiskForensics\FTK Imager\` | FTK Imager | Exterro registration form (not redistributable) |
| `_runtime\x64\` | Microsoft Visual C++ runtime DLLs, copied next to tools that need them | included in the release package |

Run `scripts\Get-Tools.ps1` on an analyst workstation with internet access, **never on the machine being examined**. Then copy the whole folder to the removable drive you take to the endpoint.

Every tool is optional. AS4 reports which ones are missing and keeps working: Live Hunt, Live Watch, Snapshots, First Response and the evidence package need none of them.

`AS4_IR_Tool_CLI.exe -Check` lists what was found and verifies hashes against `config\tools_manifest.json`.
