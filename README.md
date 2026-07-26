# Family Control for OpenWrt

A mobile-first, person-centric internet access controller for OpenWrt.

The first release will let an administrator:

- create a person;
- assign one or more devices to that person;
- pause or resume internet access for all of the person's devices; and
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

Release `r12` adds an optional, disabled-by-default OpenTelemetry metrics
exporter for Grafana Cloud. It reports aggregate Family Control enforcement
health and basic router health without exporting names, MAC addresses, IP
addresses, hostnames, or browsing activity.

See [docs/telemetry.md](docs/telemetry.md) for the metric catalog, Grafana
configuration, secret handling, dashboard import, and operational behavior.

## Installing a development build

The package built for OpenWrt 25.12.4 is:

```text
dist/luci-app-familycontrol-0.1.0-r12.apk
SHA-256: 3fc03ae90fb2d70c63f721efb45a713781fe129b909bac072d8e7b282423ee70
```

Copy it to the router, install it, and restart rpcd:

```sh
ssh root@openwrt \
  'cat > /tmp/luci-app-familycontrol-0.1.0-r12.apk' \
  < dist/luci-app-familycontrol-0.1.0-r12.apk
ssh root@openwrt
apk add --allow-untrusted /tmp/luci-app-familycontrol-0.1.0-r12.apk
/etc/init.d/rpcd restart
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
statically configured devices.

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
