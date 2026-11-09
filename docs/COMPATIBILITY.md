# Compatibility and impact on the machine

## Windows versions
| System | What to expect |
|---|---|
| Windows 10, 11, Server 2016 and later (64-bit) | Supported. Everything above was tested on Windows 11 Pro 26200. |
| Windows 7 SP1, 8.1, Server 2008 R2 to 2012 R2 | **Not tested.** Needs Windows PowerShell 5.1 (WMF 5.1) installed; `AS4_IR_Tool_CLI.exe -Check` tells you. Collection tasks that use newer cmdlets (for example `Get-NetTCPConnection`, `Get-MpComputerStatus`) fail one by one and are recorded as FAILED; the rest keeps running. The bundled Hayabusa, Chainsaw, YARA and Volatility are recent builds and may not start on these systems; AS4 then reports the tool as not runnable and skips it. |
| 32-bit Windows | Not tested. The bundled tools are 64-bit. Put a 32-bit build in `tools\` (for Hayabusa a `hayabusa-*-win-x86.exe` is picked up automatically on 32-bit Windows). |
| Windows on ARM | x64 tools run through Windows emulation; not tested. |

Best practice for old machines: collect on the machine with the built-in commands, then copy the exported logs to a newer analysis machine and run Quick Scan there (Quick Scan only needs the `.evtx` files).

## Runtime libraries (works on a clean machine)
Some bundled tools need Microsoft Visual C++ runtime DLLs that many machines do not have (FTK Imager needs `mfc100u.dll`; Chainsaw and YARA need `vcruntime140.dll`). AS4 ships the unmodified, Microsoft-signed DLLs in `tools\_runtime\x64` and copies the ones a tool imports next to it when that tool is first used. The check reads the program's import table, so it also covers tools you add later. Nothing is installed and nothing outside the AS4 folder is changed.

Program types that need something else and that AS4 cannot supply: .NET Framework 4.x programs (KAPE, gkape; included in Windows 10 and 11) and newer .NET runtime programs (Arsenal Image Mounter). Hayabusa and the Volatility executable carry what they need, but use the Universal C Runtime that is part of Windows 10 and later.

## How gentle it is
- Every program AS4 starts, and AS4 itself, runs at **below-normal priority**, so the user's applications keep priority.
- Hayabusa uses **half of the CPU cores** unless you choose a number (Hayabusa Advanced, `--threads`).
- Logs are only **read**; nothing is changed, installed, stopped or deleted. Output goes to the AS4 folder only.
- No sorting of results in memory by default (`--sort` is off), so memory use stays small. Measured here: about 25 MB of logs scanned with 5,000 rules in 4 to 5 seconds.
- Quick Scan can be run later on **copies** of the logs on another machine, which puts no load on the endpoint at all.
- No network: nothing is downloaded, uploaded or looked up. The HTML reports have no external links.
- Live commands still touch the running system lightly (processes are started, Prefetch entries may be written); see `EVIDENCE_HANDLING.md`.