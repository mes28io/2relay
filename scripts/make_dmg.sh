#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_cmd hdiutil
require_cmd rsync
require_cmd mktemp
require_cmd ln
require_cmd osascript
require_cmd codesign
require_cmd security
require_cmd awk

dist_dir="$(default_dist_dir)"
app_path="${1:-${dist_dir}/export/2relay.app}"
[[ -d "${app_path}" ]] || die "app not found: ${app_path}"

output_dmg="${2:-${dist_dir}/2relay.dmg}"
rw_dmg="${dist_dir}/2relay-rw.dmg"
tmp_output="${dist_dir}/2relay-compressed.dmg"
volume_name="2relay"
device=""

staging_dir="$(mktemp -d "${dist_dir}/dmg-staging.XXXXXX")"
cleanup() {
  if [[ -n "${device}" ]]; then
    hdiutil detach "${device}" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "${staging_dir}" "${rw_dmg}" "${tmp_output}"
}
trap cleanup EXIT

rsync -a "${app_path}" "${staging_dir}/"
ln -s /Applications "${staging_dir}/Applications"

rm -f "${output_dmg}" "${rw_dmg}" "${tmp_output}"
echo "[2relay] creating DMG: ${output_dmg}"
hdiutil create \
  -volname "${volume_name}" \
  -srcfolder "${staging_dir}" \
  -fs HFS+ \
  -format UDRW \
  "${rw_dmg}" \
  >/dev/null

attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "${rw_dmg}")"
device="$(printf '%s\n' "${attach_output}" | awk '/Apple_HFS/ {print $1; exit}')"
[[ -n "${device}" ]] || die "failed to mount read-write DMG."

osascript <<EOF >/dev/null
tell application "Finder"
    tell disk "${volume_name}"
        open
        delay 0.2
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {140, 120, 860, 520}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 14
        set position of item "2relay.app" of container window to {190, 250}
        set position of item "Applications" of container window to {520, 250}
        update without registering applications
        delay 0.2
        close
    end tell
end tell
EOF

hdiutil detach "${device}" -quiet
device=""

hdiutil convert "${rw_dmg}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${tmp_output}" \
  >/dev/null

mv "${tmp_output}" "${output_dmg}"

allow_unsigned_dmg="${ALLOW_UNSIGNED_DMG:-0}"
if [[ "${allow_unsigned_dmg}" == "1" ]]; then
  echo "[2relay] ALLOW_UNSIGNED_DMG=1; skipping DMG code signing."
else
  dmg_sign_identity="${DMG_SIGN_IDENTITY:-}"
  if [[ -z "${dmg_sign_identity}" ]]; then
    if [[ -n "${TEAM_ID:-}" ]]; then
      dmg_sign_identity="$(
        security find-identity -v -p codesigning 2>&1 \
          | awk -F '"' -v team="${TEAM_ID}" '/Developer ID Application:/ && index($2, "(" team ")") > 0 { print $2; exit }'
      )"
    else
      dmg_sign_identity="$(
        security find-identity -v -p codesigning 2>&1 \
          | awk -F '"' '/Developer ID Application:/ { print $2; exit }'
      )"
    fi
  fi

  [[ -n "${dmg_sign_identity}" ]] || die "could not find Developer ID Application identity to sign DMG. Set DMG_SIGN_IDENTITY or TEAM_ID."
  echo "[2relay] signing DMG with: ${dmg_sign_identity}"
  codesign --force --sign "${dmg_sign_identity}" --timestamp "${output_dmg}"
fi

echo "[2relay] done: ${output_dmg}"
