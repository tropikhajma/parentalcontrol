# Family Control for OpenWrt

A mobile-first, person-centric internet access controller for OpenWrt.

The first release will let an administrator:

- create a person;
- assign one or more devices to that person;
- pause or resume internet access for all of the person's devices; and
- use the same LuCI interface remotely over Tailscale.

See [docs/design.md](docs/design.md) for the initial architecture and scope.

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

## Installing a development build

Add `luci-app-familycontrol` to the `applications` directory of an OpenWrt LuCI
checkout or expose this repository as a custom feed, then build it with the
OpenWrt 25.12 SDK:

```sh
./scripts/feeds update luci
./scripts/feeds install luci-app-familycontrol
make package/luci-app-familycontrol/compile V=s
```

Install the resulting `.apk` on the router and restart rpcd:

```sh
apk add --allow-untrusted /tmp/luci-app-familycontrol-*.apk
/etc/init.d/rpcd restart
```

The application appears under **Services → Family Control**. Configure people
and devices first, then use the Overview page for pause/resume.

Do not publish LuCI on the WAN. Connect to its Tailscale address to manage it
remotely.
