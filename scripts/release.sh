#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_cmd gh
require_cmd git

# Usage: ./scripts/release.sh 0.2.0
# Builds, packages, uploads to GitHub, updates appcast, and pushes.

version="${1:-}"
[[ -n "${version}" ]] || die "usage: $0 <version>  (e.g. 0.2.0)"

version="$(normalize_marketing_version "${version}")"
tag="v${version}"
dist_dir="$(default_dist_dir)"

echo ""
echo "========================================="
echo "  2relay release ${tag}"
echo "========================================="
echo ""

# 1. Build
echo "[release] building app..."
TWORELAY_MARKETING_VERSION="${version}" "${SCRIPT_DIR}/build_release.sh"

app_path="${dist_dir}/export/2relay.app"
[[ -d "${app_path}" ]] || die "build failed: ${app_path} not found"

# 2. Create release zip (for curl installer)
echo ""
echo "[release] creating release zip..."
"${SCRIPT_DIR}/make_release_zip.sh"

# 3. Create Sparkle update zip
echo ""
echo "[release] creating Sparkle update zip..."
"${SCRIPT_DIR}/make_update_zip.sh" "${app_path}"

build_version="$(bundle_value "${app_path}" CFBundleVersion)"
update_zip="${dist_dir}/updates/2relay-${version}-${build_version}.zip"
[[ -f "${update_zip}" ]] || die "update zip not found: ${update_zip}"

# 4. Create DMG
echo ""
echo "[release] creating DMG..."
"${SCRIPT_DIR}/make_dmg.sh"

# 5. Create GitHub release and upload assets
echo ""
echo "[release] creating GitHub release ${tag}..."
gh release create "${tag}" \
  "${dist_dir}/2relay-macos.zip" \
  "${dist_dir}/2relay-macos.zip.sha256" \
  "${update_zip}" \
  "${dist_dir}/2relay.dmg" \
  --title "${tag}" \
  --notes "Release ${tag}" \
  --repo "mes28io/2relay"

echo "[release] assets uploaded"

# 6. Update appcast.xml for Sparkle in-app updates
echo ""
echo "[release] updating appcast.xml..."
DOWNLOAD_BASE_URL="https://github.com/mes28io/2relay/releases/download/${tag}" \
APPCAST_BASE_URL="https://raw.githubusercontent.com/mes28io/2relay/main" \
SPARKLE_PRIVATE_KEY_PATH="${SPARKLE_PRIVATE_KEY_PATH:-${HOME}/.config/2relay/sparkle_ed25519_key}" \
"${SCRIPT_DIR}/write_appcast.sh" "${update_zip}" "${app_path}"

# 7. Commit and push appcast
echo ""
echo "[release] pushing appcast.xml..."
git -C "${REPO_ROOT}" add appcast.xml
git -C "${REPO_ROOT}" commit -m "Update appcast for ${tag}"
git -C "${REPO_ROOT}" push origin main

echo ""
echo "========================================="
echo "  release ${tag} complete!"
echo "========================================="
echo ""
echo "  GitHub: https://github.com/mes28io/2relay/releases/tag/${tag}"
echo "  Sparkle will pick up the update automatically."
echo "  curl installer will download ${tag} as latest."
echo ""
