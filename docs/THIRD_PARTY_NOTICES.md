# Third-party components

AS4 IR Tool starts these programs as separate processes and does not link them into its own code. Licence texts are in `docs\licenses\` and inside the tool folders. This is a summary, not legal advice.

| Component | Version | Licence | Source |
|---|---|---|---|
| Hayabusa (Yamato Security) | 4.2.0 | AGPL-3.0 (program); rules under the Detection Rule License 1.1 | https://github.com/Yamato-Security/hayabusa and https://github.com/Yamato-Security/hayabusa-rules |
| Chainsaw (WithSecure Labs) | 2.17.1 | GPL-3.0 (`tools\Chainsaw\chainsaw\LICENCE`) | https://github.com/WithSecureLabs/chainsaw |
| Sigma rules (bundled with Chainsaw) | as shipped | Detection Rule License 1.1 (`tools\Chainsaw\chainsaw\sigma\LICENSE`) | https://github.com/SigmaHQ/sigma |
| YARA (VirusTotal) | 4.5.5 | BSD-3-Clause | https://github.com/VirusTotal/yara |
| WinPmem (Velocidex) | 4.0 rc2 | Apache-2.0 | https://github.com/Velocidex/WinPmem |

Source code for the GPL and AGPL components is available at the links above. Hayabusa and Chainsaw are used unmodified.

Optional tools that are **not** included in the published package and must be obtained by each user under their own licence: KAPE (Kroll), FTK Imager (Exterro), Sysinternals tools (Microsoft), Volatility 3 (Volatility Foundation, Volatility Software License), and any extra tools placed in `tools\Other`.

The detection ideas in Quick Scan (MITRE ATT&CK tactics, log-coverage checks, failed-then-successful logon pattern) are general DFIR practice; MITRE ATT&CK is a trademark of The MITRE Corporation.

## Microsoft Visual C++ runtime (tools\_runtime)
Unmodified, Microsoft-signed runtime DLLs taken from Microsoft's own redistributable installers (Visual C++ 2015-2022 14.44.35211 and Visual C++ 2010 SP1 10.0.40219) so that the bundled tools run on machines without those redistributables. They are redistributed under Microsoft's terms for the Visual C++ runtime; see `tools\_runtime\README.txt` for sources and `tools\_runtime\x64\SHA256SUMS.txt` for hashes.
