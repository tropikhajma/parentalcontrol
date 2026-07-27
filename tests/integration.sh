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
		echo "$status" | jsonfilter -e "@.people[0].devices[0].connected" |
			grep -qx false

		ubus call familycontrol save_calendar \
			"{\"day_off\":[\"2026-10-30\"],\"school_day\":[\"2026-11-17\"]}" \
			>/dev/null
		test "$(uci get familycontrol.main.day_off)" = 2026-10-30
		test "$(uci get familycontrol.main.school_day)" = 2026-11-17
		invalid_date="$(ubus call familycontrol save_calendar \
			"{\"day_off\":[\"2026-02-30\"],\"school_day\":[]}")"
		echo "$invalid_date" | jsonfilter -e "@.code" | grep -qx invalid_date

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

		# A schedule with no online slots blocks the person. Extra time grants
		# temporary access, and tick restores enforcement when it expires.
		zeros=000000000000000000000000000000000000000000000000
		ubus call familycontrol save_schedule \
			"{\"person\":\"alice\",\"school_schedule\":\"$zeros\",\"dayoff_schedule\":\"$zeros\",\"school_night_cutoff\":1320,\"dayoff_night_cutoff\":1320}" \
			>/dev/null
		ubus call familycontrol set_mode \
			"{\"person\":\"alice\",\"mode\":\"schedule\"}" >/dev/null
		uci -q get firewall.familycontrol_alice >/dev/null
		extra="$(ubus call familycontrol add_extra \
			"{\"person\":\"alice\",\"minutes\":15}")"
		echo "$extra" | jsonfilter -e "@.extra_until" | grep -Eq "^[0-9]+$"
		! uci -q get firewall.familycontrol_alice
		uci set familycontrol.alice.extra_until=1
		uci commit familycontrol
		ubus call familycontrol tick >/dev/null
		uci -q get firewall.familycontrol_alice >/dev/null
		reloads="$(wc -l </tmp/firewall-reloads)"
		ubus call familycontrol tick >/dev/null
		test "$(wc -l </tmp/firewall-reloads)" = "$reloads"

		# A device added to an already paused person is blocked immediately.
		added="$(ubus call familycontrol save_device \
			"{\"person\":\"alice\",\"name\":\"New phone\",\"mac\":\"DE:AD:BE:EF:00:01\"}")"
		echo "$added" | jsonfilter -e "@.ok" | grep -qx true
		new_device="$(echo "$added" | jsonfilter -e "@.device")"
		test "$(uci get firewall.familycontrol_alice.src_mac)" = \
			"00:11:22:33:44:55 AA:BB:CC:DD:EE:FF DE:AD:BE:EF:00:01"
		duplicate="$(ubus call familycontrol save_device \
			"{\"person\":\"alice\",\"name\":\"Duplicate\",\"mac\":\"DE:AD:BE:EF:00:01\"}")"
		echo "$duplicate" | jsonfilter -e "@.code" | grep -qx duplicate_mac

		# Moving a device away from a paused person removes it from that rule.
		bob="$(ubus call familycontrol save_person \
			"{\"name\":\"Bob\"}" | jsonfilter -e "@.person")"
		ubus call familycontrol save_device \
			"{\"device\":\"$new_device\",\"person\":\"$bob\",\"name\":\"New phone\",\"mac\":\"DE:AD:BE:EF:00:01\"}" \
			>/dev/null
		test "$(uci get firewall.familycontrol_alice.src_mac)" = \
			"00:11:22:33:44:55 AA:BB:CC:DD:EE:FF"
		! uci -q get "firewall.familycontrol_$bob"

		# Removing the only device from a paused person removes its rule.
		ubus call familycontrol set_paused \
			"{\"person\":\"$bob\",\"paused\":true}" >/dev/null
		uci -q get "firewall.familycontrol_$bob" >/dev/null
		ubus call familycontrol delete_device \
			"{\"device\":\"$new_device\"}" >/dev/null
		! uci -q get "firewall.familycontrol_$bob"

		# Failed reloads restore both family configuration and firewall rules.
		touch /tmp/firewall-fail
		failed="$(ubus call familycontrol save_device \
			"{\"person\":\"alice\",\"name\":\"Failed phone\",\"mac\":\"DE:AD:BE:EF:00:02\"}")"
		echo "$failed" | jsonfilter -e "@.ok" | grep -qx false
		echo "$failed" | jsonfilter -e "@.code" | grep -qx firewall_reload_failed
		! uci show familycontrol | grep -q "DE:AD:BE:EF:00:02"
		test "$(uci get firewall.familycontrol_alice.src_mac)" = \
			"00:11:22:33:44:55 AA:BB:CC:DD:EE:FF"
		rm /tmp/firewall-fail

		# Deleting a paused person removes devices and the generated rule.
		ubus call familycontrol delete_person \
			"{\"person\":\"alice\"}" >/dev/null
		! uci -q get familycontrol.alice
		! uci -q get familycontrol.alice_phone
		! uci -q get familycontrol.alice_laptop
		! uci -q get firewall.familycontrol_alice
		fw4 check

		telemetry="$(ucode \
			/src/luci-app-familycontrol/root/usr/libexec/familycontrol-otel-payload)"
		echo "$telemetry" | jsonfilter \
			-e "@.resourceMetrics[0].resource.attributes[0].value.stringValue" |
			grep -qx familycontrol
		echo "$telemetry" |
			grep -Eq "\"name\":[[:space:]]*\"familycontrol.enforcement.drift\""
		echo "$telemetry" |
			grep -Eq "\"name\":[[:space:]]*\"familycontrol.action.duration\""
	'

echo "OpenWrt integration checks passed."
