#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_cmd ditto
require_cmd shasum
require_cmd dirname
require_cmd basename

dist_dir="$(default_dist_dir)"
app_path="${1:-${dist_dir}/export/2relay.app}"
zip_path="${2:-${dist_dir}/2relay-macos.zip}"
checksum_path="${3:-${zip_path}.sha256}"

[[ -d "${app_path}" ]] || die "app not found: ${app_path}"

mkdir -p "$(dirname "${zip_path}")"
rm -f "${zip_path}" "${checksum_path}"

echo "[2relay] creating release zip: ${zip_path}"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${zip_path}"

(
  cd "$(dirname "${zip_path}")"
  shasum -a 256 "$(basename "${zip_path}")" > "$(basename "${checksum_path}")"
)

echo "[2relay] wrote checksum: ${checksum_path}"
echo "[2relay] done"
