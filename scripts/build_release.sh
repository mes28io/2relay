#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_cmd xcodebuild
require_cmd ditto
require_cmd codesign
require_cmd awk

dist_dir="$(default_dist_dir)"
export_dir="${dist_dir}/export"
mkdir -p "${dist_dir}"
mkdir -p "${export_dir}"

project_path="${XCODE_PROJECT_PATH:-${REPO_ROOT}/mac-app/2relay.xcodeproj}"
scheme="${SCHEME:-2relay}"
archive_path="${dist_dir}/2relay.xcarchive"
archive_app="${archive_path}/Products/Applications/2relay.app"
output_app="${export_dir}/2relay.app"
team_id="${TEAM_ID:-${DEVELOPMENT_TEAM:-}}"
allow_unsigned="${ALLOW_UNSIGNED_BUILD:-0}"
marketing_version="$(default_marketing_version)"
build_version="$(default_build_version)"

[[ -d "${project_path}" ]] || die "missing project: ${project_path}"

echo "[2relay] archiving ${scheme} from ${project_path}..."
echo "[2relay] app version: ${marketing_version} (${build_version})"
if [[ -n "${team_id}" ]]; then
  echo "[2relay] using DEVELOPMENT_TEAM=${team_id}"
else
  echo "[2relay] TEAM_ID not set; using team configured in Xcode project."
fi
if [[ "${allow_unsigned}" == "1" ]]; then
  echo "[2relay] ALLOW_UNSIGNED_BUILD=1 (local verification mode; not notarization-ready)"
fi
rm -rf "${archive_path}"
xcodebuild_args=(
  -project "${project_path}"
  -scheme "${scheme}"
  -configuration Release
  -destination "generic/platform=macOS"
  -archivePath "${archive_path}"
  archive
  SKIP_INSTALL=NO
  MARKETING_VERSION="${marketing_version}"
  CURRENT_PROJECT_VERSION="${build_version}"
)

if [[ -n "${team_id}" ]]; then
  xcodebuild_args+=(DEVELOPMENT_TEAM="${team_id}")
fi
if [[ "${allow_unsigned}" == "1" ]]; then
  xcodebuild_args+=(CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild "${xcodebuild_args[@]}"

[[ -d "${archive_app}" ]] || die "archive missing expected app: ${archive_app}"

echo "[2relay] exporting app to ${output_app}..."
rm -rf "${output_app}"
ditto "${archive_app}" "${output_app}"

[[ -d "${output_app}" ]] || die "export failed: ${output_app} not found"

if [[ "${allow_unsigned}" == "1" ]]; then
  echo "[2relay] skipping codesign verification for unsigned build mode"
else
  # Sparkle's nested updater helpers can end up ad-hoc signed depending on how
  # Xcode signs embedded package artifacts. Re-sign nested Sparkle components
  # with the same Developer ID identity as the app before notarization.
  app_sign_details="$(codesign -dv --verbose=4 "${output_app}" 2>&1 || true)"
  app_sign_identity="$(
    printf '%s\n' "${app_sign_details}" \
      | awk -F= '/^Authority=Developer ID Application:/{print $2; exit}'
  )"

  if [[ -n "${app_sign_identity}" ]]; then
    sparkle_base="${output_app}/Contents/Frameworks/Sparkle.framework/Versions/B"
    sparkle_targets=(
      "${sparkle_base}/Autoupdate"
      "${sparkle_base}/Updater.app"
      "${sparkle_base}/XPCServices/Downloader.xpc"
      "${sparkle_base}/XPCServices/Installer.xpc"
      "${sparkle_base}/Sparkle"
      "${output_app}/Contents/Frameworks/Sparkle.framework"
    )

    for target in "${sparkle_targets[@]}"; do
      if [[ -e "${target}" ]]; then
        codesign \
          --force \
          --sign "${app_sign_identity}" \
          --timestamp \
          --options runtime \
          "${target}"
      fi
    done

    # Re-sign outer app while preserving entitlements/requirements.
    # Keep this as the only direct codesign invocation for the .app, otherwise
    # a prior forced signature can strip entitlements (for example microphone).
    codesign \
      --force \
      --sign "${app_sign_identity}" \
      --timestamp \
      --options runtime \
      --preserve-metadata=identifier,entitlements,requirements \
      "${output_app}"
  fi

  codesign --verify --deep --strict --verbose=2 "${output_app}"
fi

echo
echo "[2relay] archive app: ${archive_app}"
echo "[2relay] exported app: ${output_app}"
echo
echo "Next:"
echo "  ./scripts/make_dmg.sh"
echo "  ./scripts/notarize_dmg.sh dist/2relay.dmg"
echo
echo "Verification:"
echo "  spctl -a -vv dist/2relay.dmg"
