#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

repo_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

shellcheck \
	"$repo_dir/tests/check.sh" \
	"$repo_dir/tests/integration.sh" \
	"$repo_dir/tests/shellcheck.sh" \
	"$repo_dir/tests/zap-baseline.sh" \
	"$repo_dir/luci-app-familycontrol/root/etc/init.d/familycontrol-scheduler" \
	"$repo_dir/luci-app-familycontrol/root/etc/init.d/familycontrol-telemetry" \
	"$repo_dir/luci-app-familycontrol/root/etc/uci-defaults/96-familycontrol-scheduler" \
	"$repo_dir/luci-app-familycontrol/root/etc/uci-defaults/97-familycontrol-schedule" \
	"$repo_dir/luci-app-familycontrol/root/etc/uci-defaults/98-familycontrol-telemetry" \
	"$repo_dir/luci-app-familycontrol/root/etc/uci-defaults/99-familycontrol-http" \
	"$repo_dir/luci-app-familycontrol/root/usr/sbin/familycontrol-scheduler" \
	"$repo_dir/luci-app-familycontrol/root/usr/sbin/familycontrol-otel-export" \
	"$repo_dir/luci-app-familycontrol/root/usr/sbin/familycontrol-otel-loop"
