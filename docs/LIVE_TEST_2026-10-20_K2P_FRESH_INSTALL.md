# K2P clean application installation — 2026-10-20

The user authorized clean installation testing on the existing Padavan device. This removes the project installation and RAM overlays while retaining firmware, LAN/Wi-Fi settings, and unrelated applications; it is not a factory reset or a fresh firmware flash.

Before testing, the complete Storage, raw Storage flash, NVRAM, runtime resources, effective profile, authenticated API state, and current selector choices were saved privately on the computer. The verified offline core archive matched the running executable. The production installer was given explicit private inputs, with the user's active node retained in the generated profile. No credentials or backup files are included here.

## First trial: failed, original service recovered

The old project directory, core, RAM resources and bind overlays were removed; the real first-install preflight passed. Actual installation exposed duplicate storage of the approximately 9 MB offline core archive on the 45 MiB tmpfs. Extraction failed with `No space left on device`. This is a failed installation test, not a pass.

The offline staging now shares the verified archive's inode when possible, copies only when linking is unavailable, and accepts an already-staged archive without removing its input. Regression tests check these ownership and fallback cases.

The trial also exposed a native startup dependency: with an unset WAN-firewall flag, the first native stop can remove the firmware loopback allow rule before readiness; the deployed LAN readiness request has no request deadline. Fresh configurations now explicitly leave WAN/INPUT protection to Padavan (`fw_wan=OFF`). The K2P readiness override uses the authenticated LAN API with connection/request deadlines, bounds retries, and removes only a temporary router-local rule it inserted.

Recovery tooling initially extracted a whole live Storage snapshot, replacing database inodes held by the firmware database daemon and consuming additional tmpfs space. The live database was preserved and the daemon reopened its files. The test rollback was narrowed to project files and the affected startup script. This maintenance-tool failure is recorded separately from the installer defects. Original profile bytes, three selector choices and a real HTTPS 204 request were subsequently verified. No router reboot or AX5 change was performed.

## Corrected trial

The corrected real first-install trial also failed and is not accepted. Automatic affected-only recovery succeeded: the original configuration bytes, all three selector choices and HTTPS 204 were verified; NVRAM comparison found no changed keys. No new reboot was performed.

Subsequent isolated device checks passed: public cold-cache domain-rule download with the exact pinned hash, native core validation of the generated first-install profile, domestic-rule import, and startup preparation with only the flash-save call stubbed. The latter does not validate flash writes or a successful installation. The next investigation must retain the failure diagnostics before rollback, especially startup preparation and first-import Storage persistence. The precise second-trial failure is still unresolved; a failed log capture cannot be replaced by an assumed cause.

The coupled long observation stopped itself after read retries during the authorized K2P maintenance. That interruption is attributed to maintenance, not to an AX5 failure. Original samples remain intact. An independent AX5-only observer now continues without being reset by K2P work; no observation gap is concatenated into a continuous 24-hour pass.

## Diagnostic trial

A third real first-install trial, with failure evidence collected before rollback, also failed. Its clean-state and native preflight checks passed. The normalized profile passed the native check, and the actual first normalization save reported 466,313 bytes written successfully to Storage. This narrows this trial away from the earlier suspected first-save failure; it does not validate the final installed flash archive or a clean boot.

The retained boot events identify the failure as no live authenticated core API within 90 seconds after native start dispatch (dispatch status zero). The native background dispatch status alone is therefore insufficient to count startup success. The precise underlying core-start failure remains unresolved. Diagnostics now also retain the bounded native `ShellCrash.log` and `core_test.log` tails, in addition to service, event and normalization logs. The third trial predates those two added tails; do not assume its evidence includes them.

Affected-only recovery again verified byte-identical original configuration, all three selector choices, HTTPS 204 and no NVRAM key changes. K2P observation resumed in a separate window after this intentional maintenance; AX5 observation was not reset. No reboot, final RC release, or clean-install pass is claimed.

## Cold preparation and persistence follow-up

A phase-instrumented diagnostic trial stopped after profile preparation entered native configuration generation, before native core dispatch. The 90-second authenticated-API deadline had expired while background preparation was still progressing. The canonical boot budget is now bounded at 180 seconds, accounting for two bounded domain-asset download attempts plus configuration normalization and native checks. Authentication, mode reset, manual-stop handling and finite failure remain required.

With that budget, the uninstrumented installer reached its success message and the fresh authenticated API returned correctly. The verification then timed out on the initial management-status call, so that trial is not a complete pass. On the actual 119-node input the conservative bypass scanner took 25.82 seconds per pass; setting a byte locale did not improve it (25.16 seconds). Skipping complete quoted tokens through the regex engine reduced the native check to 5.68 seconds, retaining character-state handling across chunk boundaries. Native old/new domestic-fallback output was byte-identical (104,674 bytes); measured end-to-end generation took 47.33 and 27.64 seconds respectively. Tests cover escaped quotes, braces, Unicode and long tokens, and preserve refusal of conflicting route rules.

The next uninstrumented trial passed bootstrap but failed at final persistence. Native afstart also saves Storage asynchronously; previously its busy lock and genuine write failures both returned 1. Storage save now reports contention as 75, and the installer retries only that result for at most 75 seconds. It preserves the existing owner's lock and still rolls back on actual write failure. Regression coverage verifies contention retry, preservation of another writer's lock/archive, and the existing genuine-failure rollback cases.

All intermediate trials retained their failure results and recovered the original profile, selector choices, HTTPS connectivity and unchanged NVRAM. A final canonical full-chain verification is recorded separately; these intermediate results must not be promoted to a clean-install or final RC pass.

## Completed first-install chain and configuration integrity

The canonical corrected first-install chain passed: confirmed application absence, native preflight, installation, authenticated API, 14 selectors, real HTTPS 204 through the proxy, and decompression/inspection of the saved Storage flash archive. A subsequent configuration-integrity run also passed, preserving enabled/insecure/server-name settings for all 101 outbounds carrying TLS settings. Fresh installations now explicitly use `skip_cert=KEEP`; existing user preferences are retained. These are first-install passes, not new router-reboot passes.

Both successful runs restored byte-identical original configuration, the three original selector choices, HTTPS 204 and unchanged NVRAM. The final management optimization reports eligibility and its priority warning from one parse. It was separately tested with the real fresh profile in an isolated native status environment (6.02 seconds, below the browser's 10-second deadline); conservative eligibility and invalid-config refusal remain covered. This isolated status check does not replace installation testing.

The verified runtime fixes were then written atomically to the restored installation and persisted. Their hashes were checked against source. The core PID and configuration bytes did not change, all three selectors were retained, current-node HTTPS returned 204, and NVRAM comparison again found no changed keys. A cache-cold management-status call on the restored installation took 2.94 seconds. The final source passed 209 K2P Python tests, 29 JS scripts, 122 repository-level tests, build/baseline checks and whitespace validation.

A new independent K2P observation window began after authorized maintenance. AX5 observation and scheduled forensic capture were preserved throughout. No new router reboot, continuous 24-hour pass, sustained-load/OOM clearance, complete cross-version upgrade matrix or final RC3 release is claimed.
