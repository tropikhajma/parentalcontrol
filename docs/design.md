# Initial design

## Product boundary

The application supports:

1. people;
2. devices identified by MAC address;
3. assigning devices to a person;
4. online, paused, and scheduled access modes;
5. accumulating temporary extra-time overrides;
6. school-day/day-off calendars and evening cutoffs; and
7. a responsive standalone interface usable through Tailscale.

Usage reporting, content filtering, and a separate cloud service remain
deliberately deferred.

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
        option mode 'schedule'
        option school_schedule '000000000000111111111111111111111111111111110000'
        option dayoff_schedule '000000000000111111111111111111111111111111110000'
        option school_night_cutoff '1320'
        option dayoff_night_cutoff '1320'

config device
        option id 'alice_phone'
        option name 'Alice phone'
        option mac '00:11:22:33:44:55'
        option person 'alice'
```

UCI section names are stable machine identifiers. Display names may change. MAC
addresses are normalized by the enforcement backend. Narrow backend CRUD
methods validate their format, ownership, and uniqueness; the restricted family
account has no generic UCI write access.

Shared devices are not assigned to several people in the first release. They
remain unassigned and unmanaged.

## Enforcement boundary

`familycontrol` is the source of truth. Generated firewall state is an
implementation detail and must be recognizable as application-owned.

Every person/device mutation and pause/resume follows this transaction:

1. acquire the Family Control mutation lock;
2. validate identifiers, names, ownership, uniqueness, and MAC addresses;
3. snapshot Family Control and application-owned firewall state;
4. apply the desired configuration and regenerate all application-owned rules;
5. reload the firewall once; and
6. report success, or restore both snapshots when reload fails.

The implementation must cover both IPv4 and IPv6 forwarded internet traffic.
Local LAN access is unaffected by default.

The initial implementation generates a named firewall4 rule for each paused
person. The rule rejects all protocols, covers both address families, and
contains every valid MAC assigned to that person. Direct nftables sets are a
later optimization if measurements show that firewall reload latency is
unacceptable.

The standalone app is the configuration interface. The older generic LuCI
People & Devices form was removed because direct UCI writes could bypass the
transaction and leave paused state out of sync with enforcement.

## Schedule model

Schedules are 48-bit strings, one bit per local half-hour. Today's
school/day-off classification selects the slot map. Tomorrow's classification
selects the evening cutoff, which is deliberately independent from the slot
map. Czech statutory holidays for 2026–2035 are installed into UCI; weekends
and those holidays are days off unless explicitly overridden. Local
`day_off` and `school_day` lists cover school-specific exceptions, with
`school_day` taking precedence.

A minute-aligned procd service asks the backend to reconcile effective access.
The reconciliation is idempotent: if generated firewall rules already equal
the desired state, it neither writes UCI nor reloads firewall4. All manual
mode changes cancel an extra-time override. Repeated extra-time grants extend
the existing override or the nearest scheduled cutoff.

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
