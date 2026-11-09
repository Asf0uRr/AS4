<p align="center"><img src="assets/hero.png" alt="AS4 IR Tool" width="100%"></p>

You get called because a machine is "acting weird". Maybe it's a finance laptop, maybe a server nobody wants to restart. You have a few minutes before somebody pulls the plug, and you are not allowed to install anything on it.

That's the situation this was built for. AS4 is one folder. Put it on a USB stick, walk up to the machine, double-click, and it does what you'd otherwise do by hand in a very stressed hour: grabs the things that disappear first, looks around, and tells you in plain words whether something smells wrong.

It only looks. It never kills a process, deletes a file, clears a log, changes a setting or touches the network.

## What it feels like

You open it, type a case name, and click **First Response**. Then pick what you think you're dealing with:

<p align="center"><img src="assets/first-response.png" alt="First Response" width="88%"></p>

AS4 collects in the order the evidence dies: connections and processes first, then files, then logs. Then it runs the **Live Hunt** and shows you this:

<p align="center"><img src="assets/live-hunt.png" alt="Live Hunt" width="88%"></p>

A verdict you can read at 3 a.m., the reasons behind it, and a list of leads. Click one:

<p align="center"><img src="assets/live-hunt-detail.png" alt="A lead explained" width="88%"></p>

Each lead says what was seen, why it matters, what to do next, and which MITRE technique it maps to. At the bottom there's a list of what the check could *not* see (no admin, a log that's off, anything that lives only in memory). A tool that only ever says "all clear" is lying to you, so this one tells you where it's blind.

*(The screenshots use made-up names and sample findings.)*

## What the Live Hunt actually looks at

About thirty seconds, low priority, read-only.

- A `svchost.exe` living in the wrong folder, or a `lsass.exe` with the wrong parent. A name that's one letter off a Windows process.
- Word, Excel or a web server starting PowerShell. Encoded and download commands. An LSASS dump. Backups being deleted, logs being cleared.
- Unsigned programs running out of Temp, Downloads or Public. A program whose file has already been deleted.
- Programs that never use the network, talking to the internet.
- Around twenty places malware hides to survive a reboot: Run keys, tasks, services, WMI, IFEO, Winlogon, AppInit, COM hijacks, a swapped `sethc.exe`.
- New local admins, a disabled Defender, exclusions, firewall off, RDP wide open, a port forward you didn't make.
- Event logs: services installed, logs cleared, Defender detections, RDP logins from the internet, password guessing that ended in a success.
- Names of attack tools in Prefetch, services and installed software, and the pipe names Cobalt Strike likes.

The rules aren't buried in code. They're lines in `config/profiles/live_indicators.json`. If your network has something that looks suspicious but isn't, delete the line. If you know a new trick, add one.

## Three more tricks

**Live Watch** sits quietly for as long as you tell it and writes down what starts, connects and resolves. If something phones home on a steady rhythm, it points at it.

**Snapshots**: take one, do the thing, take another, compare. You see exactly what was added, removed or changed. You can also compare against a snapshot from a clean machine of the same build.

**Quick Scan**: have a folder of `.evtx` logs from somewhere else? Point AS4 at it and it runs the Hayabusa rules and gives you the same kind of verdict, with an attack chain and an incident window.

And the usual toolbox is in there too: live-response commands, Prefetch, Amcache, Shimcache, jump lists, browser history, SRUM, event-log export, memory and disk imaging (WinPmem, FTK Imager), KAPE, Hayabusa with 21 ready-made questions, Chainsaw, YARA, IOC search, a UTC timeline. Everything it saves goes in a numbered case folder with a SHA-256 ledger and a manifest of every command, so you can show later exactly what you did.

## It ignores itself

Running a scanner on a machine creates a lot of events that look exactly like what it's hunting: PowerShell scripts, process starts, files in Temp. AS4 filters its own footprint out of every verdict and tells you how many items it dropped. The raw logs are never touched.

## Using it

| | |
|---|---|
| `AS4_IR_Tool.exe` | the window |
| `AS4_IR_Tool_Admin.exe` | the same, as administrator. It sees a lot more: Security log, Prefetch, every process path. |
| `AS4_IR_Tool_CLI.exe` | console menus. `-Check` tests the folder, `-Batch hunt -Case "Name"` runs unattended. |
| `scripts\Start-Without-Exe.cmd` | for machines whose policy blocks unsigned exe files |

The exes are small launchers around `app\Main.ps1` and are not code-signed. Sign them with your own certificate using `scripts\Build-Exe.ps1 -SignThumbprint <cert>` if you need that.

## On a machine you don't trust

Run it from a USB stick and keep `output\` there. AS4 writes only inside its own folder. I watched Temp, AppData, ProgramData and Windows\Temp during a full First Response run: nothing was created or changed.

Everything it needs is in the folder, down to the Visual C++ runtime DLLs. It downloads nothing and installs nothing. It runs at low priority, and on a server or a busy CPU it drops into a gentler mode on its own (pauses, no file scan, fewer signature checks). A full Live Hunt on my workstation takes about half a minute and half of one core at low priority.

Windows will still record that programs ran (Prefetch, event logs). That's unavoidable. The only optional item that writes to the registry is Autoruns, which wants to remember that you accepted its licence. It's off by default and the console warns you first.

## What I won't pretend

- Running anything changes a live machine. Memory capture is never free.
- A live view can't see code that exists only in memory, or code that hides from Windows itself. If you suspect that, capture memory.
- Without administrator it can't read the Security log, Prefetch or other users' process paths. The report says so.
- A hit is a lead, not a verdict. You decide.
- Tested on Windows 10 and 11, 64-bit. Older Windows, 32-bit and ARM are untested.

## What's in the folder

```
AS4\
  app\        the engine and the two interfaces
  tasks\      one file per job: Live Hunt, Live Watch, Scenarios, Hayabusa, Artifacts, ...
  config\     rules and presets, plain JSON
  tools\      third-party programs, each one optional (tools\README.md)
  output\     one folder per case
  scripts\    fetch tools, self-test, build the exes and the release
  assets\     images for this README
  licenses\   licence texts of the bundled programs
```

Case folders are numbered so you can find things half asleep: `01_System_Info`, `02_Network`, ... `12_Reports`, `13_Collection_Logs`, `14_Live_Analysis`.

## Build and test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Test-AS4.ps1    # self-test, synthetic data only
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Build-Exe.ps1   # the launcher exes
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\New-Release.ps1  # dist\AS4_IR_Tool_<version>.zip
```

The release zip carries only what the licences allow: Hayabusa, Chainsaw, YARA, WinPmem and the Microsoft runtime DLLs. KAPE, FTK Imager and the Sysinternals tools are yours to add (`tools\README.md` says how). Every tool is optional; Live Hunt, Live Watch, Snapshots and First Response need none of them.

## When something goes wrong

- **Windows blocks the exe** (Smart App Control, WDAC, SmartScreen): the exes are unsigned launchers. Use `scripts\Start-Without-Exe.cmd`, or sign them with your own certificate.
- **Lots of items say SKIPPED, "requires administrator":** start `AS4_IR_Tool_Admin.exe`.
- **A tool says a DLL is missing** (`mfc100u.dll`, `VCRUNTIME140.dll`): AS4 copies the right runtime from `tools\_runtimed` next to the tool on first use. `-Check` shows if anything is still missing.
- **KAPE, FTK Imager, Volatility or Sysinternals show MISSING:** they aren't redistributable. `tools\README.md` says how to add them. Everything else works without them.
- **`output\ writable: FAIL`:** the drive is read-only or write-blocked. Use a writable one.
- **`query user` says FAILED (exit 1):** Windows returns 1 when there is no session to list. Harmless.
- **Where are the logs?** `output\<case>_Collection_Logs\` (`session.log` and `manifest.jsonl`).

## Licence

MIT for the AS4 code (`LICENSE`). Bundled programs keep their own licences (texts in `licenses`). Only use it on systems you're allowed to examine.
