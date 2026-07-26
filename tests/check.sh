#!/bin/sh
set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

node --check \
	"$repo_dir/luci-app-familycontrol/htdocs/luci-static/resources/view/familycontrol/overview.js"
node --check \
	"$repo_dir/luci-app-familycontrol/htdocs/luci-static/resources/view/familycontrol/manage.js"

jq empty \
	"$repo_dir/luci-app-familycontrol/root/usr/share/luci/menu.d/luci-app-familycontrol.json" \
	"$repo_dir/luci-app-familycontrol/root/usr/share/rpcd/acl.d/luci-app-familycontrol.json"

docker run --rm --platform linux/amd64 \
	-v "$repo_dir/luci-app-familycontrol/root/usr/share/rpcd/ucode/familycontrol:/src/familycontrol:ro" \
	openwrt/rootfs:x86_64 \
	ucode -c -o /tmp/familycontrol.uc /src/familycontrol

"$repo_dir/tests/integration.sh"

echo "Static checks passed."
