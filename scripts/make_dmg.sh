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
  rm -rf "${staging_dir}" "${rw_dmg}" "${tmp_output}" "${dist_dir}/2relay-initial.dmg" "${dist_dir}/2relay-ro.dmg"
}
trap cleanup EXIT

rsync -a "${app_path}" "${staging_dir}/"
ln -s /Applications "${staging_dir}/Applications"

# Check for background image (will be copied onto mounted volume later)
bg_source="${REPO_ROOT}/scripts/resources/dmg-background.png"
if [[ -f "${bg_source}" ]]; then
  has_background=1
else
  has_background=0
fi

rm -f "${output_dmg}" "${rw_dmg}" "${tmp_output}"
echo "[2relay] creating DMG: ${output_dmg}"

# Create initial read-only DMG, then convert to true read-write
initial_ro="${dist_dir}/2relay-ro.dmg"
initial_dmg="${dist_dir}/2relay-initial.dmg"
rm -f "${initial_ro}" "${initial_dmg}"
hdiutil create \
  -volname "${volume_name}" \
  -srcfolder "${staging_dir}" \
  -fs HFS+ \
  -format UDRO \
  "${initial_ro}" \
  >/dev/null

hdiutil convert "${initial_ro}" -format UDRW -o "${initial_dmg}" >/dev/null
rm -f "${initial_ro}"
hdiutil resize -size 100m "${initial_dmg}" >/dev/null 2>&1 || true

attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "${initial_dmg}")"
device="$(printf '%s\n' "${attach_output}" | awk '/Apple_HFS/ {print $1; exit}')"
[[ -n "${device}" ]] || die "failed to mount read-write DMG."

# Copy background into mounted volume's hidden .background folder
if [[ "${has_background}" == "1" ]]; then
  mkdir -p "/Volumes/${volume_name}/.background"
  cp "${bg_source}" "/Volumes/${volume_name}/.background/background.png"
fi

osascript <<EOF >/dev/null
tell application "Finder"
    tell disk "${volume_name}"
        open
        delay 0.5
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {140, 120, 860, 520}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 160
        set text size of opts to 14
        if ${has_background} is 1 then
            set background picture of opts to file ".background:background.png"
        end if
        set position of item "2relay.app" of container window to {180, 200}
        set position of item "Applications" of container window to {530, 200}
        update without registering applications
        delay 0.5
        close
    end tell
end tell
EOF

hdiutil detach "${device}" -quiet
device=""

hdiutil convert "${initial_dmg}" \
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
