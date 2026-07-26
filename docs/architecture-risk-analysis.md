# Architecture risk analysis

Date: 2026-07-26

Scope: Family Control `0.1.0-r14`, the live OpenWrt 25.12.4 deployment, its
standalone web interface, rpcd/ucode backend, UCI and firewall4 integration,
Endora DNS, Let's Encrypt/ACME-DNS certificate automation, and the planned
Tailscale connection. It also covers the optional Grafana Cloud OpenTelemetry
metrics export introduced in `r13`.

This is a qualitative engineering assessment, not a penetration test or a
guarantee of security. It uses the current source, live non-secret router
configuration, passive ZAP results, and direct protocol checks. Ratings combine
likelihood and impact for this household use case.

## Executive assessment

The current deployment has a sound outer boundary: WAN input is rejected,
there is no WAN HTTP/HTTPS exception, unauthenticated ubus calls are denied,
the family account has a dedicated rpcd ACL, and the backend does not
interpolate user input into shell commands.

The largest risks are inside that boundary:

1. displayed policy can diverge from actual firewall policy after device edits;
2. the application is still usable over unencrypted HTTP;
3. the restricted account can perform generic UCI writes instead of using
   validated domain operations;
4. the family interface shares uHTTPd and an origin with the full LuCI surface;
5. MAC addresses are convenient identifiers, not strong device identities.

The first three should be addressed before adding remote access or schedules.
Tailscale should be treated as transport-level access control, not as a
replacement for application authorization.

## Assets and security objectives

| Asset | Objective |
| --- | --- |
| Router administrative control | A family-interface compromise must not become root/LuCI control. |
| Enforcement integrity | “Paused” must mean every currently assigned device is blocked. |
| Internet availability | A UI or reload failure must not unnecessarily disrupt unrelated devices. |
| Family credentials and session | Credentials and session tokens must not be observable or reusable by another LAN/tailnet device. |
| Family configuration | People, device identifiers, and assignments must remain valid and recoverable. |
| Household metadata | Names, MAC addresses, hostnames, and IP addresses should not leave the router unintentionally. |
| Grafana write credential | Compromise must not grant read access, dashboard administration, or authority outside metrics ingestion. |
| Telemetry integrity | Metrics and alerts should reflect router state without becoming part of the enforcement path. |
| Recovery access | A TLS, DNS, firewall, or Tailscale failure must not lock the owner out of the router. |

## Actors and assumptions

- The owner is trusted with root and LuCI administration.
- A spouse is trusted to manage Family Control, but should not need or receive
  router administration rights.
- A child or managed-device user may intentionally try simple bypasses such as
  MAC randomization or spoofing.
- A compromised or hostile LAN/IoT device can send traffic to router services
  and may attempt credential theft, brute force, or cross-origin attacks.
- A compromised tailnet account or enrolled device becomes a remote network
  actor once Tailscale is enabled.
- Endora, Let's Encrypt, ACME-DNS, Grafana Cloud, OpenWrt package repositories,
  GitHub Actions, npm, and container registries are supply-chain or availability
  dependencies.

Physical access to the router, compromise of the owner's root credentials, and
attacks against OpenWrt itself are relevant but outside the application's
ability to prevent.

## Trust boundaries

```text
                 Endora DNS
                     |
           Let's Encrypt <- ACME-DNS
                     |
                     v
wife browser -- LAN/Tailscale -- uHTTPd :443
                                  |  \
                         /family + /ubus \ LuCI/root login
                                  |
                          rpcd family ACL
                                  |
                         familycontrol ucode
                            |           |
                      UCI config    firewall UCI
                                        |
                                  firewall4/nftables
                                        |
                              managed device traffic

familycontrol metrics -- outbound HTTPS/OTLP --> Grafana Cloud
```

The important shared boundary is uHTTPd: the simple interface, ubus endpoint,
OpenWrt landing page, and LuCI login are served by the same process and origin.
The rpcd ACL limits what an authenticated family session may call, but it does
not reduce the web code and endpoints exposed on that origin.

## Existing controls verified

- WAN input policy is `REJECT`; no rule opens TCP 80 or 443 from WAN.
- uHTTPd serves a valid Let's Encrypt certificate for `family.hajma.cz`.
- An unauthenticated call to `familycontrol.status` returns `Access denied`.
- The `familycontrol` rpcd login has only the
  `luci-app-familycontrol` read/write ACL.
- The ACL restricts UCI access to the `familycontrol` package.
- Backend person identifiers and MAC addresses are validated before firewall
  rule creation.
- Firewall commands are fixed strings rather than user-built shell commands.
- A failed firewall reload attempts to restore the previous firewall section.
- UI-provided names and discovered-device labels are HTML-escaped before
  insertion.
- ACME and ACME-DNS secrets are root-only and excluded from Git.
- Grafana telemetry is disabled by default, uses HTTPS, and stores its
  metrics-write token in a root-readable UCI file.
- Exported metrics are aggregate and contain no person names, MAC addresses,
  IP addresses, hostnames, browsing activity, or unbounded device attributes.
- Grafana failure is fail-open for observability: batches are dropped after a
  ten-second timeout and access-control operations continue locally.
- The Grafana authorization value is written to a mode `0600` temporary file,
  is not placed in process arguments, and is removed after each attempt.
- A deterministic CycloneDX SBOM records the locked npm development graph and
  declared OpenWrt runtime packages; CI rejects a stale SBOM and retains it as
  an artifact.
- Passive ZAP testing is local and its reports are excluded from Git.

## Prioritized risk register

### R1 — Paused state can drift from device assignments

**Rating: High — current**

Firewall rules are generated only by `set_paused`. Adding, removing, or
changing a device uses generic UCI methods and does not regenerate an existing
paused person's rule. A new device may therefore retain internet access while
the UI says the person is paused. A removed device may remain blocked until
the person is resumed. Direct UCI deletion of a paused person can also leave an
orphan firewall rule.

**Mitigation:** Make all mutations backend domain operations. Under a lock,
validate the complete configuration, write it, reconcile all
`familycontrol_*` firewall sections to desired state, reload, verify, and only
then report success. Reconcile on service start and after firewall restart.
Add tests for editing, moving, and deleting devices while paused.

### R2 — Credentials and sessions remain available over HTTP

**Rating: High — current**

uHTTPd returns the login application over port 80 with status 200 and does not
redirect to HTTPS. A user can submit the password and ubus session over clear
text. WPA encryption is not a substitute for application TLS when hostile or
compromised LAN devices are in scope.

**Mitigation:** Make the family hostname HTTPS-only and add HSTS after recovery
access is designed. Preserve emergency router access by IP or a separate
management listener rather than leaving the family login on HTTP. Test that
HTTP never accepts credentials.

### R3 — Generic UCI write permission bypasses domain validation

**Rating: High — current**

The family ACL grants `uci.add`, `set`, `delete`, and `commit` for the complete
`familycontrol` package. This is narrower than router-wide UCI access, but it
still lets a compromised family session bypass UI validation, change source or
destination zones, introduce duplicate MAC addresses and dangling owners, or
create state the enforcement API does not understand.

**Mitigation:** Remove UCI write methods from the family ACL. Expose narrow
backend methods such as `save_person`, `delete_person`, `save_device`, and
`delete_device`. Enforce length, type, referential-integrity, uniqueness, and
zone allow-list checks in the backend. Return a read-only model rather than
generic UCI data where practical.

### R4 — Family UI shares the LuCI administrative attack surface

**Rating: High — current**

`/family/`, `/ubus`, the OpenWrt landing page, and `/cgi-bin/luci/` share one
uHTTPd process, IP, port, and browser origin. The family ACL prevents direct
root operations, but any same-origin web vulnerability or uHTTPd/LuCI
vulnerability has a much larger blast radius than the small family UI requires.
The root login surface is also reachable from every accepted LAN client.

**Mitigation:** Give Family Control a separate IP/listener or a small reverse
proxy that exposes only `/family/` and `/ubus`. Bind LuCI/SSH to a management
address, management VLAN, or owner-only Tailscale policy. Do not rely on a
different path as an isolation boundary.

### R5 — MAC addresses are bypassable device identity

**Rating: High residual risk**

MAC matching can control ordinary household devices, but a capable user can
enable private/random MAC addressing or spoof an allowed device's address.
Duplicate addresses can also cause availability problems. This cannot be fully
fixed by stronger input validation.

**Mitigation:** Clearly document the control strength. Disable private MAC
addressing for managed SSIDs where devices permit it, reject duplicate
assignments, and alert on unknown/replaced MACs. For a stronger boundary, place
people or device classes on separate SSIDs/VLANs, ideally using per-device PSKs
or another network-authentication mechanism, and enforce by network identity
rather than client-asserted MAC alone.

### R6 — Firewall/config update is not one atomic transaction

**Rating: Medium-high — current**

Pause/resume commits and reloads the firewall before committing the displayed
paused state. Concurrent operations have no explicit lock. A process crash,
storage error, or overlapping request can produce mismatch or rollback over
another change. Reloading the whole firewall for every toggle also increases
latency and network-wide failure impact.

**Mitigation:** Serialize mutations with a lock, calculate desired state first,
use one reconciliation path, and verify both UCI and nftables state. Prefer a
dedicated nftables set/table or an include that can be changed atomically
without a full firewall reload. Maintain a last-known-good configuration.

### R7 — Missing ongoing enforcement reconciliation and health signal

**Rating: Medium-high — current**

The UI reports the UCI `paused` flag, not verified live firewall state. Manual
firewall edits, package upgrades, reload failures, or generated-rule removal
can therefore go unnoticed.

**Mitigation:** Make status compare desired configuration with rendered/live
enforcement. Show `enforced`, `pending`, or `error`, record the last successful
application, and reconcile after boot, firewall reload, and configuration
change. Log failures without including credentials or personal data.

### R8 — Password login has limited abuse resistance

**Rating: Medium — current**

The family login is reachable by all LAN clients and uses a shared password.
There is no application-level rate limit, MFA, per-user accountability, or
notification of repeated failures.

**Mitigation:** Use a long unique password stored in the phone password
manager. Add login throttling at the service/firewall layer and audit failed
attempts. When remote access is added, restrict network reachability to named
Tailscale users/devices and consider eliminating the shared application
password in favor of a trusted identity-aware proxy.

### R9 — Browser hardening is incomplete

**Rating: Medium — current**

The family responses lack CSP, `X-Content-Type-Options`, anti-framing policy,
referrer policy, and permissions policy. The page uses inline CSS and an
inline dynamic script loader, making a strict CSP harder. Its ubus token is in
`sessionStorage`, so a same-origin XSS can read it.

**Mitigation:** Move inline code and CSS to static files, send a restrictive
CSP, prevent framing, set `nosniff`, use a strict referrer policy, and enable
HSTS after HTTP is removed. Keep escaping all untrusted values and add
automated header assertions. Storage choice does not compensate for XSS;
origin isolation is the stronger control.

### R10 — Tailscale may broaden access beyond the family UI

**Rating: High if deployed with defaults — planned, not current**

Tailscale is not currently listening on the router. When enabled, permissive
tailnet defaults, a broad subnet route, or access to the router's Tailscale IP
can expose SSH, HTTP, HTTPS, DNS, LuCI, and other LAN devices—not only Family
Control.

**Mitigation:** Use a tagged router and explicit Tailscale grants allowing the
wife's approved identity/devices only to the family HTTPS listener. Do not
grant `*:*` or an entire LAN subnet unless required. Require device approval,
review key expiry, protect tailnet administration with strong authentication,
and test denied ports. Tailscale recommends explicit grants/ACLs for precise
resource access.

### R11 — Certificate issuance depends on delegated third parties

**Rating: Medium — current**

Endora controls the authoritative zone and ACME-DNS controls the delegated
challenge response. Compromise of either can enable certificate issuance.
Outage or loss of the ACME-DNS credential prevents renewal, although the
current certificate remains valid until expiry. The public private-address
record also depends on recursive resolvers accepting that answer.

**Mitigation:** Monitor expiry independently, alert well before 30 days,
retain documented credential-rotation steps, and keep Endora protected with
strong authentication. Consider a DNS provider with scoped API tokens under
the owner's account if dependency reduction becomes important.

### R12 — Unsigned builds and mutable supply-chain inputs

**Rating: Medium — current/open-source distribution**

The development APK is installed with `--allow-untrusted`. GitHub Actions use
version tags rather than immutable commit SHAs, the ZAP image uses the mutable
`stable` tag, and npm/OpenWrt/container downloads are external build inputs.
A compromised build input could produce router-privileged code.

**Mitigation:** Sign release packages, publish checksums and provenance, pin CI
actions and container images by digest, keep lock files, and separate release
signing from CI build credentials. Retain the checked-in CycloneDX SBOM, and
augment release SBOMs with the exact OpenWrt dependency versions resolved by
the package build or target installation. Treat local development packages as
non-production artifacts.

### R13 — Router is a single enforcement and administration failure domain

**Rating: Medium — current**

The UI, policy database, firewall enforcement, DNS, certificate key, and
recovery access all reside on one router. Storage failure, a bad firewall
change, or a broken upgrade can remove both enforcement and its management
plane.

**Mitigation:** Maintain tested configuration backups outside the router,
document console/failsafe recovery, export non-secret family configuration,
and test restore on upgrades. Fail visibly; do not present stale configuration
as successfully enforced.

### R14 — Household metadata can leak through diagnostics

**Rating: Low-medium — current**

The application processes people's names, MAC addresses, DHCP hostnames, and
LAN IP addresses. ZAP reports and support logs can capture internal URLs and
headers. This is modest household data, but publishing it can identify devices
and network structure.

The optional Grafana exporter adds an intentional outbound data flow. Its
current metric schema contains only aggregate counts, bounded action/result
labels, router utilization, and service metadata. A future developer could
nevertheless add a person, MAC, hostname, IP, URL, or other high-cardinality
attribute and silently turn operational metrics into household tracking data.

**Mitigation:** Keep reports ignored, redact logs and screenshots, and minimize
retention. Keep telemetry disabled by default. Treat the metric catalog and
privacy boundary in `docs/telemetry.md` as part of the security interface.
Reject identifiers and unbounded attributes in review and tests, and review
Grafana retention and access whenever the schema changes.

### R15 — Telemetry credentials and cloud observability can fail or be abused

**Rating: Low-medium — current, optional**

When enabled, the router stores a Grafana Cloud access-policy token and sends
one OTLP/HTTP batch per minute. Theft of that token could allow an attacker to
write false metrics, consume the free-tier allowance, or interfere with alerts.
Grafana compromise, account compromise, retention-policy changes, DNS/TLS
failure, or an exporter defect can remove or falsify observability. Metrics are
therefore useful evidence but not an enforcement authority. Repeated failures
can also generate a small amount of local process and network load.

The current token is intended to have only `metrics:write`; it cannot read
metrics or administer Grafana. The exporter uses HTTPS, a ten-second timeout,
no retry queue, a minimum 30-second interval, bounded labels, and `/tmp`
counters. Enforcement does not wait for or depend on Grafana.

**Mitigation:** Retain a stack-scoped `metrics:write` token only, keep the UCI
file mode `0600`, rotate the token after suspected disclosure, and never print
the telemetry configuration in diagnostics. Alert on stale telemetry from an
independent Grafana-side rule, cap label cardinality, monitor free-tier usage,
and keep local enforcement status authoritative. Consider certificate pinning
only if its operational and renewal risks are explicitly addressed.

## Recommended remediation sequence

### P0 — Before remote access or new features

1. Replace generic UCI writes with validated backend CRUD methods.
2. Add one locked reconciliation engine and use it for every mutation.
3. Reconcile edits to paused people immediately and verify live enforcement.
4. Make the family hostname HTTPS-only while preserving separate recovery
   access.
5. Add regression tests for enforcement drift, orphan rules, duplicate MACs,
   invalid owners, reload failure, and concurrent requests.

### P1 — Reduce compromise blast radius

1. Isolate Family Control from LuCI by listener/address and origin.
2. Add strict browser security headers and remove inline executable code.
3. Add login throttling and security-relevant audit events.
4. Display desired versus verified enforcement state.
5. Sign release packages and pin mutable CI/container dependencies.
6. Add automated assertions that telemetry payloads contain no household
   identifiers and that exporter failure cannot block enforcement.

### P2 — Remote access

1. Design and review a deny-by-default Tailscale grants policy first.
2. Expose only the isolated HTTPS listener to approved identities/devices.
3. Verify that SSH, LuCI, DNS, and the rest of the LAN remain unreachable.
4. Document tailnet account/device recovery and periodically review membership.

### P3 — Stronger parental-control boundary

1. Decide whether resistance to deliberate MAC spoofing is a requirement.
2. If it is, design per-person/device-class SSIDs or VLANs and enforce at that
   boundary.
3. Keep MAC grouping as UX metadata rather than the sole security identity.

## Verification targets

The architecture should not be considered ready for remote use until automated
checks demonstrate:

- HTTP cannot accept or transport family credentials;
- every configuration mutation either reconciles enforcement or fails without
  claiming success;
- live nftables state matches all paused people after boot and firewall reload;
- a family session cannot call generic write APIs or alter firewall zones;
- duplicate MACs and dangling person references are rejected;
- deleting a paused person cannot leave an orphan rule;
- failed and concurrent updates preserve a known-good state;
- the family origin cannot reach LuCI/root administration;
- Tailscale policy allows only the intended listener and denies other router
  and subnet services;
- release artifacts are reproducible, checksummed, and signed.
- telemetry payloads contain only the documented bounded attributes;
- the Grafana token is absent from process arguments, logs, and source control;
- Grafana outage or authentication failure cannot delay or alter enforcement.

## References

- [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [OWASP Application Security Verification Standard](https://owasp.org/www-project-application-security-verification-standard/)
- [OpenWrt ACME guidance](https://openwrt.org/docs/guide-user/services/tls/acmesh)
- [OpenWrt uHTTPd documentation](https://openwrt.org/docs/guide-user/services/webserver/http.uhttpd)
- [Tailscale access control](https://tailscale.com/docs/features/access-control)
- [Tailscale subnet-router guidance](https://tailscale.com/kb/1104/enable-ip-forwarding)
- [Grafana Cloud OTLP endpoint](https://grafana.com/docs/grafana-cloud/send-data/otlp/send-data-otlp/)
- [Grafana Cloud access policies](https://grafana.com/docs/grafana-cloud/security-and-account-management/authentication-and-permissions/access-policies/)
