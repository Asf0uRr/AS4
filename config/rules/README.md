# rules\ - analyst-supplied detection content (offline)

- `yara\`  put your `.yar` rule files here (used by Analysis > YARA when a YARA executable is bundled in `tools\YARA`).
- `ioc\`   IOC lists, one indicator per line (hashes, IPs, domains, URLs, paths; `#` comments allowed). `sample_iocs.txt` is a format example only - it contains reserved documentation indicators, not real threat data.
- Sigma rules and Chainsaw rules/mappings are bundled with Chainsaw under `tools\Chainsaw\chainsaw\sigma`, `rules`, `mappings`. To refresh them: download newer Sigma/Chainsaw rules on the analyst workstation from the official repositories and replace those folders there (not on the endpoint).
