# Family Control for OpenWrt

A mobile-first, person-centric internet access controller for OpenWrt.

The first release will let an administrator:

- create a person;
- assign one or more devices to that person;
- pause, resume, or schedule internet access for all of the person's devices;
- grant temporary extra time;
- distinguish school days from days off using Czech public holidays and
  school-specific exceptions; and
- use the same LuCI interface remotely over Tailscale.

See [docs/design.md](docs/design.md) for the initial architecture and scope,
and [docs/architecture-risk-analysis.md](docs/architecture-risk-analysis.md)
for the current threat model and prioritized risk register.

## Development target

- OpenWrt 25.12
- LuCI JavaScript frontend
- rpcd/ucode backend
- firewall4/nftables enforcement
- remote access through an existing Tailscale connection

The package source is in `luci-app-familycontrol/`.

## Development checks

The checks require Node.js, `jq`, Docker, and internet access for the first
OpenWrt container package download:

```sh
./tests/check.sh
```

They validate JavaScript and JSON syntax, compile the rpcd ucode plugin, and run
pause/resume through real ubus, rpcd, UCI, and firewall4 components in an
OpenWrt container.

## AWS CI/CD learning environment

An optional, manually triggered AWS CodeBuild implementation of these checks is
defined under [`aws/`](aws/README.md). Phase 1 uses OpenTofu and intentionally
creates no automatic trigger, release bucket, network path to the router, or
deployment credentials.

## Local security scan

Run an OWASP ZAP passive baseline scan from a laptop that can reach the router:

```sh
npm run test:zap
```

The command runs ZAP in Docker, maps `family.hajma.cz` to `192.168.1.1` inside
the container, and writes HTML, JSON, and Markdown reports under
`reports/zap/`. Reports are ignored by Git because they can contain details
about the local network.

The scan is deliberately not run by GitHub Actions: the target is LAN-only.
It is passive and does not perform ZAP's active attacks. Warnings are included
in the reports without making the command fail.

Override the defaults when needed:

```sh
ZAP_TARGET=https://family.hajma.cz/family/ \
ZAP_TARGET_IP=192.168.1.1 \
npm run test:zap
```

The baseline scan is unauthenticated, so it covers the login page and other
publicly reachable resources. Do not put the Family Control password in this
script or commit it to the repository.

## Privacy-safe telemetry

Release `r17` includes an optional, disabled-by-default OpenTelemetry metrics
exporter for Grafana Cloud. It reports aggregate Family Control enforcement
health and basic router health without exporting names, MAC addresses, IP
addresses, hostnames, or browsing activity.

See [docs/telemetry.md](docs/telemetry.md) for the metric catalog, Grafana
configuration, secret handling, dashboard import, and operational behavior.

## Software bill of materials

The repository includes a deterministic CycloneDX SBOM at
[`sbom/familycontrol.cdx.json`](sbom/familycontrol.cdx.json). It distinguishes
development-only npm packages from the OpenWrt runtime dependencies declared by
the application package. Regenerate and verify it with:

```sh
npm run sbom
npm run sbom:check
```

OpenWrt resolves the exact runtime package versions when the APK is installed,
so those components are identified by package name and explicitly marked as
installation-resolved. CI rejects a stale checked-in SBOM and retains the
verified file as a workflow artifact.

## Installing a development build

The package built for OpenWrt 25.12.4 is:

```text
dist/luci-app-familycontrol-0.1.0-r17.apk
SHA-256: 15ee72fe32c4742e81eb0f96acddc39d63aaf201d4b21962b064d0a0ce4efb70
```

Copy it to the router, install it, and restart rpcd:

```sh
ssh root@openwrt \
  'cat > /tmp/luci-app-familycontrol-0.1.0-r17.apk' \
  < dist/luci-app-familycontrol-0.1.0-r17.apk
ssh root@openwrt
apk add --allow-untrusted /tmp/luci-app-familycontrol-0.1.0-r17.apk
/etc/init.d/rpcd restart
/etc/init.d/familycontrol-scheduler restart
```

The package is unsigned because it is a local development build. Verify its
checksum before copying it if it is transferred through an untrusted system.

To build it from source with the OpenWrt 25.12 SDK, expose
`luci-app-familycontrol/` as an SDK package and use:

```sh
make defconfig
make NO_DEPS=1 package/luci-app-familycontrol/compile V=s
```

`NO_DEPS=1` is appropriate for this architecture-independent package: its
firewall4, LuCI, rpcd, and ucode dependencies are runtime dependencies already
provided by the router. It also prevents the release SDK's buildbot
configuration from repackaging every selected kernel module.

To uninstall the application:

```sh
apk del luci-app-familycontrol
/etc/init.d/rpcd restart
```

The application appears under **Services → Family Control**. Configure people
and devices first, then use the Overview page for pause/resume.

## Standalone family interface

Release `r9` also provides a mobile standalone interface at:

```text
https://family.hajma.cz/family/
```

It uses the separate `familycontrol` account, whose rpcd access is limited to
the Family Control API and UCI configuration. Set its password on the router
after installation:

```sh
passwd familycontrol
```

When adding a device, the interface offers current DHCP clients by hostname,
IP address, and MAC address. Manual MAC entry remains available for offline or
statically configured devices. Saved devices show a Connected or Not connected
indicator based on the router's validated neighbour table, rather than the
longer-lived DHCP lease. The page refreshes this state every 30 seconds while
no editor is open.

## Schedules and school calendar

Schedules use the router's local time. Before relying on them, make sure
OpenWrt is configured for the household's timezone. For this deployment:

```sh
uci set system.@system[0].zonename='Europe/Prague'
uci set system.@system[0].timezone='CET-1CEST,M3.5.0,M10.5.0/3'
uci commit system
/etc/init.d/system reload
/etc/init.d/rpcd restart
/etc/init.d/familycontrol-scheduler restart
```

Verify that `date` on the router reports `CET` or `CEST`. A UTC-configured
router would enforce a 22:00 cutoff at midnight during Czech summer time.

Each person can be **Online**, **Paused**, or set to **Use schedule**. Select
the person's name to edit two half-hour schedules:

- **School day** controls availability on a school day.
- **Day off** controls availability on weekends, Czech public holidays, and
  additional days off.

Two evening cutoffs answer a separate question: whether tomorrow is a school
day or a day off. This allows an earlier bedtime before school and a later one
before weekends or holidays. New schedules default to online from 06:00 to
22:00.

The **Extra time** menu adds 15, 30, or 60 minutes and can be used repeatedly.
During scheduled online time it extends the next cutoff; while paused or
outside the schedule it grants temporary online access. Choosing Online,
Paused, or Use schedule cancels the temporary override.

The bundled Czech statutory-holiday calendar covers 2026 through 2035 and is
generated deterministically with:

```sh
npm run holidays
```

Use **School calendar** in the standalone app for school vacations,
director-declared days off, or exceptional school Saturdays. An explicit
School day entry overrides weekends and public holidays; otherwise an explicit
Day off entry overrides the normal weekday classification.

For LAN name resolution, configure dnsmasq to answer locally and not forward
IPv6 queries to public DNS:

```sh
uci add_list dhcp.@dnsmasq[0].address='/family.hajma.cz/192.168.1.1'
uci add_list dhcp.@dnsmasq[0].server='/family.hajma.cz/'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

The router uses a Let's Encrypt certificate obtained with automated DNS-01
validation. The service remains limited to LAN and, eventually, Tailscale:
uhttpd is not exposed through the WAN firewall. See
[docs/https.md](docs/https.md) for DNS, certificate renewal, recovery, and
secret-handling details.

Do not publish LuCI on the WAN. Connect to its Tailscale address to manage it
remotely.

## License

Family Control is free software licensed under the
[GNU General Public License, version 3 or later](LICENSE).
