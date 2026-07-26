#!/bin/sh

set -eu

repo_dir="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
target="${ZAP_TARGET:-http://family.hajma.cz/family/}"
target_ip="${ZAP_TARGET_IP:-192.168.1.1}"
image="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"
report_dir="$repo_dir/reports/zap"

command -v docker >/dev/null 2>&1 || {
	echo "Docker is required to run the ZAP baseline scan." >&2
	exit 1
}

mkdir -p "$report_dir"

echo "Running a passive ZAP baseline scan against $target"
echo "Reports will be written to $report_dir"

docker run --rm \
	--add-host "family.hajma.cz:$target_ip" \
	-v "$repo_dir:/zap/wrk:rw" \
	"$image" \
	zap-baseline.py \
	-t "$target" \
	-j \
	-I \
	-m 1 \
	-T 5 \
	-r reports/zap/baseline.html \
	-J reports/zap/baseline.json \
	-w reports/zap/baseline.md
