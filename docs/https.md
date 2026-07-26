# HTTPS for Family Control

Family Control is served at:

```text
https://family.hajma.cz/family/
```

The hostname resolves publicly to the router's private LAN address. The router
obtains a publicly trusted Let's Encrypt certificate without opening an
internet-facing port by using DNS-01 validation through a narrowly scoped
ACME-DNS delegation.

## Architecture

The relevant DNS records at Endora are:

```text
family                  A       192.168.1.1
_acme-challenge.family  CNAME   eec72f3b-95b8-4aaf-8e2c-8eeeed067bfc.auth.acme-dns.io.
```

The CNAME grants the ACME-DNS account control only over the TXT response used
to validate `family.hajma.cz`. It does not grant access to other `hajma.cz`
records. Do not add a TXT record at `_acme-challenge.family` while the CNAME
exists.

uHTTPd continues listening on ports 80 and 443, but the OpenWrt WAN zone has an
input policy of `REJECT` and no HTTP or HTTPS allow rule. Do not add a WAN
firewall exception for either port.

## Router packages

The setup uses the OpenWrt 25.12 packages:

```text
acme-common
acme-acmesh
acme-acmesh-dnsapi
luci-ssl
uhttpd
```

The ACME scripts under `/usr/lib/acme/` are supplied and updated by those
OpenWrt packages. They are not project-authored deployment scripts and are not
vendored in this repository. No custom HTTPS script is currently deployed on
the router.

## Non-secret configuration

The equivalent `/etc/config/acme` settings are:

```uci
config acme
	option account_email 'tropikhajma@gmail.com'
	option debug '0'

config cert 'family'
	option enabled '1'
	option staging '0'
	list domains 'family.hajma.cz'
	option validation_method 'dns'
	option dns 'dns_acmedns'
	option key_type 'ec256'
	option days '30'
```

The `family` section also contains these credential variables:

```text
ACMEDNS_USERNAME
ACMEDNS_PASSWORD
ACMEDNS_SUBDOMAIN
ACMEDNS_BASE_URL
```

Their values are secrets and must never be added to source control, logs,
screenshots, bug reports, or command output. `/etc/config/acme` is mode `0600`.
The root-only ACME-DNS registration file is also excluded by the repository's
`.gitignore`.

uHTTPd uses the stable symlinks managed by the ACME package:

```uci
option cert '/etc/ssl/acme/family.hajma.cz.fullchain.crt'
option key '/etc/ssl/acme/family.hajma.cz.key'
```

The certificate private key must never leave the router or be committed.

## Renewal

`acme-common` installs this root cron entry:

```cron
0 0 * * * /etc/init.d/acme renew
```

Both cron and ACME must be enabled:

```sh
/etc/init.d/cron enable
/etc/init.d/cron start
/etc/init.d/acme enable
```

The ACME client checks nightly and renews when needed. A renewal emits the
OpenWrt ACME event used to reload uHTTPd.

Safe status checks that do not print credentials:

```sh
/etc/init.d/cron running
/etc/init.d/acme enabled
logread -e acme
openssl x509 \
	-in /etc/ssl/acme/family.hajma.cz.fullchain.crt \
	-noout -subject -issuer -dates
```

Avoid dumping the ACME service environment with `ubus call service list`; it
contains the DNS update credential.

## Initial issuance procedure

For a new router:

1. Back up `/etc/config/uhttpd`, `/etc/config/firewall`, `/etc/config/dhcp`,
   and `/etc/config/acme` if it exists.
2. Install the packages listed above.
3. Register a new ACME-DNS account and store its response in a root-only file.
4. Change the Endora CNAME to the newly returned `fulldomain`.
5. Configure the ACME credential variables in `/etc/config/acme` without
   printing them.
6. Issue from the Let's Encrypt staging server first.
7. After successful DNS validation, set `staging` to `0` and issue the
   production certificate.
8. Configure the uHTTPd certificate paths shown above and restart uHTTPd.
9. Verify the certificate from a separate machine.

Never reuse the example CNAME target for a replacement router: its matching
update credential exists only on the currently configured router.

## Verification

From a LAN machine:

```sh
curl --fail --show-error \
	--resolve family.hajma.cz:443:192.168.1.1 \
	https://family.hajma.cz/family/ \
	--output /dev/null
```

Run the local passive security scan over HTTPS:

```sh
npm run test:zap
```

Also confirm from outside the home network that the router's public address
does not accept connections on TCP ports 80 or 443.

## Backup and recovery

The initial live-router backup was created at:

```text
/root/familycontrol-https-backup-20260726-132933
```

To revert only uHTTPd, restore `uhttpd` from that directory and restart the
service:

```sh
cp /root/familycontrol-https-backup-20260726-132933/uhttpd /etc/config/uhttpd
/etc/init.d/uhttpd restart
```

If an ACME-DNS credential is exposed:

1. Register a new ACME-DNS account.
2. Replace the Endora CNAME with the new `fulldomain`.
3. Wait until both authoritative nameservers return the new CNAME.
4. Replace all four ACME-DNS credential variables on the router.
5. Publish a test TXT value through the new account.

Changing the CNAME disconnects the old credential from certificate validation
for `family.hajma.cz`. Existing certificates remain valid during rotation.
