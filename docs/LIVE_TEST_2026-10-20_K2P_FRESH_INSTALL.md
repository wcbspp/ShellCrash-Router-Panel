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
