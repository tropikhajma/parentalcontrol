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

The package built for OpenWrt 25.12.4 is:

```text
dist/luci-app-familycontrol-0.1.0-r2.apk
SHA-256: 52a58789bad8277bc5e3e66a5a52695237f0b6d4fb11816df5b597afa647f5f8
```

Copy it to the router, install it, and restart rpcd:

```sh
ssh root@openwrt \
  'cat > /tmp/luci-app-familycontrol-0.1.0-r2.apk' \
  < dist/luci-app-familycontrol-0.1.0-r2.apk
ssh root@openwrt
apk add --allow-untrusted /tmp/luci-app-familycontrol-0.1.0-r2.apk
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

Do not publish LuCI on the WAN. Connect to its Tailscale address to manage it
remotely.
