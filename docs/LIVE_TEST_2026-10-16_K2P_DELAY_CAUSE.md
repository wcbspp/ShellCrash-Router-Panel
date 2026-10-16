# K2P delay interpretation correction

The previous HTTP target change did not eliminate test-site TLS on sing-box 1.12.13. Its Clash delay handler clears any lowercase `http://` URL and the URL tester substitutes the default Gstatic HTTPS URL. See the exact upstream [handler](https://github.com/SagerNet/sing-box/blob/v1.12.13/experimental/clashapi/proxies.go#L174) and [timer](https://github.com/SagerNet/sing-box/blob/v1.12.13/common/urltest/urltest.go#L73). The timer spans proxy dialing and an HTTP HEAD request, with TLS for an HTTPS target; it is not ICMP RTT. These source observations do not by themselves prove which stage dominates this device's result.

Actual K2P proof on the currently selected AnyTLS leaf: an impossible HTTP `.invalid` target still returned 534 ms, whereas the HTTPS equivalent failed; explicit Gstatic HTTPS returned 580 and 550 ms in two independent diagnostic requests. This confirms HTTP target substitution on the actual device. It does not prove that a specific AnyTLS handshake or CPU cost accounts for the whole difference from user experience. No averaging or adjusted low number is used.

The lightweight request now explicitly uses Gstatic HTTPS and the help/tooltips describe HTTPS request time including handshakes, distinct from Ping or established-session responsiveness. This corrects a misleading previous explanation; it does not claim the K2P high-value issue has been solved. Measuring transport RTT separately or profiling fresh versus established AnyTLS sessions remains open. No node, core version or automatic group settings are changed.

Private evidence: `work/task-state/k2p-delay-cause-20261016.private/`, including original API outputs and protected state snapshots. Existing final RC gates remain open.

Native ICMP diagnostic to the selected outbound server returned 67.512 and 67.558 ms with 0% packet loss. This is router-to-node ICMP only, whereas the HTTP test includes node egress to Gstatic and request setup. It does not isolate the AnyTLS CPU or handshake component or prove TCP/application RTT equals ICMP. Separate reference measurement has not been added to the UI yet.

Regression: root112, AX87 Python26JS, K198 Python28JS passed; build/baseline checks passed. Deployed-page checks verify one explicit HTTPS request per visible node and corrected help on desktop/390px.
