#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

repo_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

docker run --rm --platform linux/amd64 --cap-add NET_ADMIN \
	-v "$repo_dir:/src:ro" \
	openwrt/rootfs:x86_64 \
	/bin/sh -ec '
		mkdir -p /usr/share/rpcd/ucode /var/lock /var/run/ubus
		cp /src/tests/fixtures/familycontrol /etc/config/familycontrol
		cp /src/tests/fixtures/firewall /etc/init.d/firewall
		cp /src/luci-app-familycontrol/root/usr/share/rpcd/ucode/familycontrol \
			/usr/share/rpcd/ucode/familycontrol
		printf "%s\n" \
			"2000000000 00:11:22:33:44:55 192.168.1.20 alice-laptop *" \
			"2000000000 DE:AD:BE:EF:00:01 192.168.1.21 new-phone *" \
			> /tmp/dhcp.leases

		apk update >/dev/null
		apk add rpcd-mod-ucode >/dev/null

		ubusd &
		sleep 1
		rpcd &
		sleep 1

		status="$(ubus call familycontrol status)"
		echo "$status" | jsonfilter -e "@.people[0].id" | grep -qx alice
		echo "$status" | jsonfilter -e "@.people[0].devices[1].mac" |
			grep -qx "AA:BB:CC:DD:EE:FF"

		devices="$(ubus call familycontrol devices)"
		echo "$devices" | jsonfilter -e "@.devices[0].hostname" |
			grep -qx alice-laptop
		echo "$devices" | jsonfilter -e "@.devices[0].assigned_person" |
			grep -qx alice
		echo "$devices" | jsonfilter -e "@.devices[1].mac" |
			grep -qx "DE:AD:BE:EF:00:01"

		ubus call familycontrol set_paused \
			"{\"person\":\"alice\",\"paused\":true}" >/dev/null

		test "$(uci get familycontrol.alice.paused)" = 1
		test "$(uci get firewall.familycontrol_alice.family)" = any
		test "$(uci get firewall.familycontrol_alice.target)" = REJECT
		test "$(uci get firewall.familycontrol_alice.src_mac)" = \
			"00:11:22:33:44:55 AA:BB:CC:DD:EE:FF"
		fw4 check

		ubus call familycontrol set_paused \
			"{\"person\":\"alice\",\"paused\":false}" >/dev/null

		test "$(uci get familycontrol.alice.paused)" = 0
		! uci -q get firewall.familycontrol_alice
	'

echo "OpenWrt integration checks passed."
