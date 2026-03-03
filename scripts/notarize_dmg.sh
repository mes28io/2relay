#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_cmd xcrun
require_cmd ls
require_cmd codesign
require_env APPLE_ID
require_env TEAM_ID
require_env APP_SPECIFIC_PASSWORD

dist_dir="$(default_dist_dir)"

if [[ -n "${1:-}" ]]; then
  dmg_path="${1}"
else
  latest_dmg="$(ls -1t "${dist_dir}"/*.dmg 2>/dev/null | head -n1 || true)"
  [[ -n "${latest_dmg}" ]] || die "no DMG found in ${dist_dir}. Pass DMG path explicitly."
  dmg_path="${latest_dmg}"
fi

[[ -f "${dmg_path}" ]] || die "DMG not found: ${dmg_path}"

if ! codesign -dv "${dmg_path}" >/dev/null 2>&1; then
  die "DMG is not signed. Rebuild with ./scripts/make_dmg.sh (or set ALLOW_UNSIGNED_DMG=0)."
fi

echo "[2relay] submitting DMG for notarization..."
xcrun notarytool submit "${dmg_path}" \
  --apple-id "${APPLE_ID}" \
  --team-id "${TEAM_ID}" \
  --password "${APP_SPECIFIC_PASSWORD}" \
  --wait

echo "[2relay] stapling ticket..."
xcrun stapler staple "${dmg_path}"
xcrun stapler validate "${dmg_path}"

echo "[2relay] notarized and stapled: ${dmg_path}"
