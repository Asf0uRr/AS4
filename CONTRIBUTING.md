# Contributing

Thanks for helping. A few rules keep the tool safe to run on machines that belong to other people.

## Ground rules

1. **Read-only on the endpoint.** Nothing in `app\` or `tasks\` may delete, stop, quarantine, install, download, change settings, or send data anywhere. `scripts\Test-AS4.ps1` (test S01) fails the build if it finds such calls.
2. **Honest results.** A task is `OK` only when it really produced what it claims. If something cannot be tested, say so (`BLOCKED`) instead of faking a result.
3. **Portable.** No hard-coded drive letters or user names. Paths are derived from the folder the tool sits in and may contain spaces.
4. **Plain words.** Findings are written for a person under time pressure: what was seen, why it matters, what to do next. Leads are leads, not verdicts.
5. **ASCII only** in `.ps1` files (Windows PowerShell 5.1 reads them without a BOM).
6. **Never commit** evidence, cases, real host names, user names, IP addresses or third-party binaries. `.gitignore` covers `output\` and `tools\`.

## Adding a detection to Live Hunt

Most detections are data, not code. Edit `config\profiles\live_indicators.json`:

- `CommandLines`: a regex, a title, a severity (`high`, `medium`, `low`), a MITRE technique, one sentence on why it matters, one sentence on what to do next.
- `Tools`: names of attack or dual-use programs (matched against process names, services, installed programs and Prefetch).
- `NamedPipes`, `NoNetworkExpected`, `SystemProcesses`: lists used by the process and network checks.

Checks that need code live in `tasks\LiveHunt.ps1` (`Test-Lh*` functions). Each returns findings made with `New-LhFinding` and must not throw: wrap fragile reads in `try`/`catch`.

## Adding a First Response scenario

Add an object to `config\profiles\scenarios_collect.json` listing task ids, artifact ids and event log groups. `scripts\Test-AS4.ps1` (test SC01) checks that every id exists.

## Testing

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Test-AS4.ps1
```

The suite uses a throw-away case and synthetic data. It reports `PASS`, `FAIL` or `BLOCKED` (for things that need administrator, a memory image or similar). Run it on a copy of the folder, not on a machine that holds real cases.

## Pull requests

Describe what changed and how you tested it. Mention anything that needs administrator or a specific Windows version. Do not paste real evidence into issues.
