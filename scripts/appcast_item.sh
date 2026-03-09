#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_cmd stat
require_cmd date
require_cmd sed
require_env DOWNLOAD_BASE_URL
require_env APPCAST_BASE_URL
require_env SPARKLE_PRIVATE_KEY_PATH

artifact_path="${1:-}"
[[ -n "${artifact_path}" ]] || die "usage: $0 /abs/path/to/update.zip [/abs/path/to/2relay.app]"
[[ -f "${artifact_path}" ]] || die "artifact not found: ${artifact_path}"

app_path="${2:-$(default_dist_dir)/export/2relay.app}"
if [[ -d "${app_path}" ]]; then
  short_version="$(bundle_value "${app_path}" CFBundleShortVersionString)"
  build_version="$(bundle_value "${app_path}" CFBundleVersion)"
else
  short_version="${SHORT_VERSION:-}"
  build_version="${VERSION:-}"
fi

[[ -n "${short_version}" ]] || die "missing short version. Pass app path or set SHORT_VERSION."
[[ -n "${build_version}" ]] || die "missing build version. Pass app path or set VERSION."

artifact_name="$(basename "${artifact_path}")"
download_url="${DOWNLOAD_BASE_URL%/}/${artifact_name}"
pub_date="$(LC_ALL=C date -Ru)"
length="$(stat -f%z "${artifact_path}")"

case "${artifact_name##*.}" in
  zip) enclosure_type="application/octet-stream" ;;
  dmg) enclosure_type="application/x-apple-diskimage" ;;
  *) enclosure_type="application/octet-stream" ;;
esac

sign_output="$("${SCRIPT_DIR}/sign_update.sh" "${artifact_path}")"
ed_signature="$(printf '%s\n' "${sign_output}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "${ed_signature}" ]]; then
  # Fallback in case sign_update prints only raw signature.
  ed_signature="$(printf '%s\n' "${sign_output}" | tr -d '[:space:]' | head -n1)"
fi
[[ -n "${ed_signature}" ]] || die "failed to parse EdDSA signature from sign_update output"

if [[ "${APPCAST_INCLUDE_HINT:-1}" == "1" ]]; then
  cat <<EOF
<!-- Add this item to ${APPCAST_BASE_URL%/}/appcast.xml -->
<item>
  <title>2relay ${short_version}</title>
  <pubDate>${pub_date}</pubDate>
  <sparkle:version>${build_version}</sparkle:version>
  <sparkle:shortVersionString>${short_version}</sparkle:shortVersionString>
  <enclosure url="${download_url}" length="${length}" type="${enclosure_type}" sparkle:edSignature="${ed_signature}" />
</item>
EOF
else
  cat <<EOF
<item>
  <title>2relay ${short_version}</title>
  <pubDate>${pub_date}</pubDate>
  <sparkle:version>${build_version}</sparkle:version>
  <sparkle:shortVersionString>${short_version}</sparkle:shortVersionString>
  <enclosure url="${download_url}" length="${length}" type="${enclosure_type}" sparkle:edSignature="${ed_signature}" />
</item>
EOF
fi
