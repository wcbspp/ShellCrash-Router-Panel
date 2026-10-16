# Single kernel node delay

The lightweight node list used the core delay endpoint three times per visible node and displayed the minimum successful sample. It now calls the same endpoint once per node and displays its returned delay directly. The existing test URL, 3000 ms core timeout, sequential queue, memory protection, visibility cancellation and request budget remain in place. A failure is shown immediately without an automatic retry; clicking the result starts a new test. Cancelled requests cannot publish a late result. Both profiles' “切换与保存” help and tooltips describe the single request and distinguish latency from download throughput.

Regression coverage executes the queue with instrumented API calls: one GET per unique node, URL encoding, direct returned value, explicit retest, timeout without retries, cancellation and pressure protection. These are controlled tests, not real node availability evidence.

Live verification and protected state evidence are recorded privately under `work/task-state/node-delay-single-20261016.private/`. This UI change does not satisfy the remaining final RC release gates.

Validation: root 112 tests; AX5 87 Python and 26 JS scripts; K2P 198 Python and 28 JS scripts passed. Build and reviewed baseline checks passed. Actual deployed pages issued exactly 10 delay requests for 10 visible AX5 nodes and 1 request for 1 visible K2P node; no control writes, page errors or help overflow at 1200/390 px. Both device configurations, core PID, boot ID and cron remained unchanged. Results prove request behavior on these visible nodes, not availability of all subscription nodes. No core restart or restore was performed.
