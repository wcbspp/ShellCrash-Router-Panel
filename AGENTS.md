# Project rules

Work on one main branch. Common UI and exact shared scripts belong under shared/, firmware interfaces under profiles/. Generated build/ and dist/ are ignored; do not edit them as canonical source.

Run build, baseline check, root tests and the relevant device suites after behavior changes. Record intentional migration differences explicitly; never update expected hashes just to hide a failing comparison.

K2P supports only service-provider direct subscriptions and same-provider compatibility download. Reject unsupported requests in the backend, not only by hiding controls. Respect its memory and Storage budgets; do not add resident services or dependencies on-device.

Preserve current user configuration before live tests, use a single K2P management client, and restore tested settings with evidence. Keep credentials, private subscriptions, device identifiers and backup archives out of source and public artifacts. Screenshots must be reviewed for sensitive content.

Public releases require documented installation, update, recovery, reboot, routing/DNS and menu/button tests on both profiles. A passed mock or offline test is not a passed device test. Do not delete old repositories during the migration; the user approved a fresh project without old commits, not premature loss of recovery sources.
