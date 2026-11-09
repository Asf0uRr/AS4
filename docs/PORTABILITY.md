# Portability

- The launcher exe finds its own folder (the fallback cmd uses `%~dp0`) and `Main.ps1` derives the root from its location. No drive letters, no dependence on the current directory. Paths are passed to programs with correct quoting.
- Needs on the endpoint: Windows with Windows PowerShell 5.1 in Full Language mode. Nothing is installed; the GUI uses WinForms that ships with Windows.
- Writes only inside the AS4 folder (`output\`), plus any destination you choose (for example a memory dump drive). `-Check` tests that `output\` is writable (read-only USB or write blocker).
- Side effects on the endpoint are listed in `EVIDENCE_HANDLING.md`.

## Tested
| Scenario | Result |
|---|---|
| Original folder a folder path that contains a space | Environment check passed |
| Copy in `...\Test Root X\AS4 copy` mapped to drive `Z:` | Passed: check, GUI (12 pages), CLI session, unattended batch, 44-test run |
| Arabic case name (`output\<name>`) | Folder created correctly |
| Real USB, FAT32/exFAT | Not tested (no USB available) |
| Windows 10, Windows Server | Not tested |
