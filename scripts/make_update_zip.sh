#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_cmd ditto

dist_dir="$(default_dist_dir)"
updates_dir="${dist_dir}/updates"
mkdir -p "${updates_dir}"

app_path="${1:-${dist_dir}/export/2relay.app}"
[[ -d "${app_path}" ]] || die "app not found: ${app_path}"

short_version="$(bundle_value "${app_path}" CFBundleShortVersionString)"
build_version="$(bundle_value "${app_path}" CFBundleVersion)"
zip_path="${2:-${updates_dir}/2relay-${short_version}-${build_version}.zip}"

rm -f "${zip_path}"
echo "[2relay] creating Sparkle update zip: ${zip_path}"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${zip_path}"

echo "[2relay] done: ${zip_path}"
