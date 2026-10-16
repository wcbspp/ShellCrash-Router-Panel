# Node delay target alignment

The lightweight page displays the numeric `delay` returned by the core; browser, HTTP controller and queue wall time are not added. Its target was Google HTTPS. Inspection of the installed advanced assets shows AX5 Yacd-Meta defaults to Gstatic HTTPS and K2P YACD to Gstatic HTTP; advanced settings can override those defaults. The API route is already the same node delay route.

A controlled live comparison of two selected leaf nodes per router measured Google HTTPS, Gstatic HTTPS and Gstatic HTTP once each, with the second node in reverse URL order. AX5 results in that order were 629/430/123 ms and 352/344/278 ms. K2P were 416/568/636 ms and 552/501/770 ms. These are individual observations, not averages, statistical attribution or guaranteed improvements. HTTP did not improve the K2P samples; route and node variability remains. Configuration, PID, boot ID and cron fingerprints were unchanged.

The lightweight test now uses `http://www.gstatic.com/generate_204`, matching the installed K2P advanced default and avoiding test-site TLS negotiation. The core's actual returned value remains authoritative. Node transport setup and protocol handshakes can still affect it; this is HTTP latency, not ICMP RTT or download speed. The page help and tooltip make that distinction. This change does not alter routing, nodes, website HTTPS detection or automatic groups' health-check URLs.

Private evidence: `work/task-state/node-delay-diagnosis-20261016.private/`. Original URL comparisons and installed advanced assets are retained; no secret or node identity is published here. Remaining final RC gates stay open.

Validation: root 112 tests, AX5 87 Python/26 JS and K2P 198 Python/28 JS passed. Build and reviewed baseline checks passed. Actual browser checks on both deployed pages verified one Gstatic HTTP request per visible node and matching help at desktop and 390 px widths, with no control writes or page errors.
