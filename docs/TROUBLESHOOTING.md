# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Chainsaw shows "NOT RUNNABLE ... Application Control policy has blocked this file" | The host's Smart App Control / WDAC / AppLocker policy refuses the unsigned binary (it happened on this workstation earlier and later cleared). AS4 does **not** bypass it. Have the policy owner allow the binary (e.g. by hash), run on a permitted analysis machine against exported EVTX, or use a signed alternative. Collection and other features are unaffected. |
| `ConvertFrom-Json: Unrecognized escape` | A config/profile JSON has a single backslash in a string; use `/` or `\\`. |
| Many tasks SKIPPED "requires administrator" | Launch with `AS4_IR_Tool_Admin.exe` (UAC). |
| Security log export fails / skipped | Needs elevation; "Access denied" is recorded in the manifest. Audit policy is never changed - if auditing was off, the log may lack events. |
| `query user` FAILED exit 1 | Windows returns 1 when no user sessions exist; output and stderr are still saved. |
| Window shows nothing / script blocked | PowerShell is in ConstrainedLanguage mode or script execution is blocked by policy: `AS4_IR_Tool_CLI.exe -Check` reports it. |
| "output\ writable: FAIL" | USB is read-only/write-blocked. Use a writable AS4 drive. |
| GUI looks frozen during a long command | It stays responsive (message pump); use **Cancel** to stop after the running command is killed. |
| Locked file copy failed (SRUDB.dat, NTUSER.DAT, Amcache) | Recorded as `FAILED` in `_inventory.csv`. Use KAPE or FTK Imager (raw read) or image the disk. |
| Memory acquisition "Insufficient space" | Free space must exceed RAM x 1.05 + 1 GB at the destination. FAT32 also caps files at 4 GB. |
| Tool shows `PRESENT_UNVERIFIED` | Hash not registered. On the analyst workstation: `scripts\Prepare-Tools.ps1 -Register`. `PRESENT_HASH_MISMATCH` blocks acquisition tools until resolved. |
| Where are logs? | `output\<case name>\13_Collection_Logs\` (session.log and manifest.jsonl). |
| Register output says no image found | FTK Imager wrote somewhere else. Make sure the destination was the case folder (it was copied to the clipboard), or the file extension is not .mem .raw .dmp .dd .E01 .001. |
| Volatility says symbols are missing | Run scripts\Get-Tools.ps1 (without -NoSymbols) on the analyst workstation to add tools\Volatility3\symbols\windows.zip. |
| Windows blocks AS4_IR_Tool.exe (Smart App Control, WDAC, SmartScreen) | The exe files are unsigned launchers, so strict policies refuse them. Use `scripts\Start-Without-Exe.cmd` (same arguments), or sign the exes with your own code-signing certificate: `scripts\Build-Exe.ps1 -SignThumbprint <thumbprint>`. AS4 does not bypass the policy. |
| A tool stops with "mfc100u.dll was not found" (FTK Imager) or "VCRUNTIME140.dll was not found" (Chainsaw, YARA) | The machine does not have that Visual C++ runtime installed. AS4 copies the right DLLs from `tools\_runtime\x64` next to the tool the first time it is used (and `-Check` does it for all tools), so the tool folder works on any machine without installing anything. If the AS4 folder is read-only, AS4 falls back to a search path pointing at `tools\_runtime\x64`. If you add a tool that needs another runtime, put its DLLs in `tools\_runtime\x64`. |
| KAPE, gkape, NetworkMiner, Arsenal Image Mounter do not start | They are .NET programs. Windows 10 and 11 include the required .NET Framework 4.x; newer Arsenal Image Mounter builds need the .NET desktop runtime. These cannot be copied next to the tool the way the C++ runtime can. |
