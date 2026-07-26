# Initial design

## Product boundary

The first vertical slice supports:

1. people;
2. devices identified by MAC address;
3. assigning devices to a person;
4. pausing and resuming a person; and
5. a responsive LuCI interface usable through Tailscale.

Weekly schedules, expiring overrides, usage reporting, content filtering, and a
separate cloud service are deliberately deferred.

## Supported platform

The initial development and deployment target is:

- OpenWrt 25.12.4 (`r32933-4ccb782af7`)
- target `mediatek/filogic`
- MERCUSYS MR90X v1 (`mercusys,mr90x-v1`)
- Linux 6.12
- firewall4/nftables
- the `apk` package manager used by OpenWrt 25.12

The application itself remains architecture-independent. OpenWrt 25.12 is the
initial minimum supported release; support for 24.10/opkg can be evaluated
after the first working release rather than constraining the initial design.

Remote access is transport only:

```text
browser -> Tailscale -> uhttpd/LuCI -> rpcd -> local policy
```

The application does not manage Tailscale accounts, keys, or router enrollment.
LuCI remains responsible for authentication and authorization.

## Technology

- LuCI client-side JavaScript with JSDoc types
- rpcd ucode backend
- UCI persistence
- firewall4-compatible enforcement
- shell only for package/install integration where OpenWrt requires it

No resident Go, Node.js, or Python service is planned for the first release.

## Domain model

The application owns a separate UCI package named `familycontrol`.

Conceptual configuration:

```uci
config settings 'main'
        option enabled '1'

config person
        option id 'alice'
        option name 'Alice'
        option paused '0'

config device
        option id 'alice_phone'
        option name 'Alice phone'
        option mac '00:11:22:33:44:55'
        option person 'alice'
```

UCI section names are stable machine identifiers. Display names may change. MAC
addresses are normalized by the enforcement backend. The management UI
validates their format; duplicate-address validation is still to be added.

Shared devices are not assigned to several people in the first release. They
remain unassigned and unmanaged.

## Enforcement boundary

`familycontrol` is the source of truth. Generated firewall state is an
implementation detail and must be recognizable as application-owned.

Pause/resume follows this transaction:

1. validate the requested person and all assigned MAC addresses;
2. update generated firewall state;
3. reload only what is necessary;
4. verify that the new state was accepted; and
5. persist or report the result without silently claiming success.

The implementation must cover both IPv4 and IPv6 forwarded internet traffic.
Local LAN access is unaffected by default.

The initial implementation generates a named firewall4 rule for each paused
person. The rule rejects all protocols, covers both address families, and
contains every valid MAC assigned to that person. Direct nftables sets are a
later optimization if measurements show that firewall reload latency is
unacceptable.

## Existing `luci-app-access-control`

The upstream package at `k-szuster/luci-access-control` was inspected at commit
`93235df0f5f235675624b8f31c5aeee1e1aeea83` (2020-01-02).

It is useful as a UX and behavior reference, but not as a current backend:

- its README says it was tested on Barrier Breaker and Chaos Calmer;
- its UI uses the legacy Lua CBI framework;
- it writes rules directly into `/etc/config/firewall`;
- generated rules contain legacy iptables-specific `--kerneltz` data;
- temporary access is implemented by toggling firewall rule `enabled` values;
- it restarts the entire firewall after changes; and
- its daemon and init script predate current procd conventions.

Therefore this project will not depend on or mutate that package's private
fields. It will reproduce the useful access-control behavior on current
firewall4 and may later provide an explicit importer for old rules.

## Security constraints

- Do not expose LuCI directly to the public internet.
- Remote access documentation will assume a private Tailscale connection.
- rpcd methods receive the narrowest practical ACL permissions.
- User-provided values are never interpolated into shell commands.
- The UI must show enforcement failures rather than optimistic state.

## First implementation milestone

The package now contains:

- a mobile-first overview;
- UCI forms for people and devices;
- an ACL-limited rpcd ucode API;
- pause/resume across the JavaScript -> rpcd -> UCI -> firewall4 boundary; and
- a container integration test using OpenWrt's actual ubus, rpcd, UCI, and fw4.

The next milestone is on-router installation and validation, followed by device
discovery and stricter cross-record validation.
