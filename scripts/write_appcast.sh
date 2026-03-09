#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_env DOWNLOAD_BASE_URL
require_env APPCAST_BASE_URL
require_env SPARKLE_PRIVATE_KEY_PATH

artifact_path="${1:-}"
app_path="${2:-}"
output_path="${3:-${REPO_ROOT}/appcast.xml}"

[[ -n "${artifact_path}" ]] || die "usage: $0 /abs/path/to/update.zip /abs/path/to/2relay.app [output.xml]"
[[ -f "${artifact_path}" ]] || die "artifact not found: ${artifact_path}"
[[ -d "${app_path}" ]] || die "app not found: ${app_path}"

item_xml="$(APPCAST_INCLUDE_HINT=0 "${SCRIPT_DIR}/appcast_item.sh" "${artifact_path}" "${app_path}")"

cat > "${output_path}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>2relay Updates</title>
    <link>${APPCAST_BASE_URL%/}/appcast.xml</link>
    <description>Latest release updates for 2relay.</description>
    <language>en</language>
${item_xml}
  </channel>
</rss>
EOF

echo "[2relay] wrote appcast: ${output_path}"
