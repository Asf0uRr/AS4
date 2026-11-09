# Security policy

## Reporting a problem

If you find a way for AS4 to modify, delete or send data from the machine it runs on, or a way a crafted file, event log or process name could make it run code, please report it privately through the repository's **Security advisories** page instead of opening a public issue. Include the Windows version, whether AS4 ran as administrator, and the steps to reproduce.

## What AS4 promises

- It makes no network connections of its own and downloads nothing on the machine it examines. (Windows' own signature check may contact certificate authorities for revocation data when the machine is online; disconnect the network first if you need zero traffic.)
- It does not stop, delete, quarantine or change anything on that machine. It writes only inside `output\<case>\`.
- It hashes what it writes (SHA-256) and seals each run.

## What it cannot promise

Running any program changes a live system (new processes, Prefetch entries, event log records). The README lists the limits. Findings are leads for a person to confirm, not proof.

## Supported versions

The latest release. Older ones are not patched.
