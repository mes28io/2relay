#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "missing required command: ${cmd}"
}

require_cmd curl
require_cmd ditto
require_cmd shasum
require_cmd uname
[[ -x "/usr/libexec/PlistBuddy" ]] || die "missing required tool: /usr/libexec/PlistBuddy"

[[ "$(uname -s)" == "Darwin" ]] || die "this installer only supports macOS."

repo="${TWORELAY_REPO:-mes28io/2relay}"
asset_name="${TWORELAY_ASSET_NAME:-2relay-macos.zip}"
version="${TWORELAY_VERSION:-latest}" # Use a tag like v0.2.0 to pin a version.
open_after_install="${TWORELAY_OPEN_AFTER_INSTALL:-1}"
install_dir="${TWORELAY_INSTALL_DIR:-}"

if [[ -z "${install_dir}" ]]; then
  if [[ -w "/Applications" ]]; then
    install_dir="/Applications"
  else
    install_dir="${HOME}/Applications"
  fi
fi

mkdir -p "${install_dir}" || die "could not create install directory: ${install_dir}"
[[ -w "${install_dir}" ]] || die "install directory is not writable: ${install_dir}"

if [[ "${version}" == "latest" ]]; then
  download_url="https://github.com/${repo}/releases/latest/download/${asset_name}"
else
  download_url="https://github.com/${repo}/releases/download/${version}/${asset_name}"
fi
checksum_url="${download_url}.sha256"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/2relay-install.XXXXXX")"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

zip_path="${tmp_dir}/${asset_name}"
checksum_path="${zip_path}.sha256"
unpack_dir="${tmp_dir}/unpack"
dest_app="${install_dir}/2relay.app"

mkdir -p "${unpack_dir}"

echo "[2relay] downloading ${download_url}"
curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 15 --progress-bar "${download_url}" -o "${zip_path}"

if curl --fail --location --retry 2 --connect-timeout 15 --silent --show-error "${checksum_url}" -o "${checksum_path}"; then
  (
    cd "${tmp_dir}"
    shasum -a 256 -c "$(basename "${checksum_path}")"
  ) || die "checksum verification failed for ${asset_name}"
  echo "[2relay] checksum verified"
else
  echo "[2relay] checksum file not found; skipping verification"
fi

ditto -x -k "${zip_path}" "${unpack_dir}"

source_app="${unpack_dir}/2relay.app"
if [[ ! -d "${source_app}" ]]; then
  source_app="$(find "${unpack_dir}" -maxdepth 3 -type d -name "2relay.app" -print -quit)"
fi
[[ -n "${source_app:-}" && -d "${source_app}" ]] || die "2relay.app was not found in downloaded archive."

case "${dest_app}" in
  "/Applications/2relay.app"|"${HOME}/Applications/2relay.app"|*/2relay.app) ;;
  *) die "refusing to install to unexpected destination: ${dest_app}" ;;
esac

pkill -f "/2relay.app/Contents/MacOS/2relay" >/dev/null 2>&1 || true
rm -rf "${dest_app}"
ditto "${source_app}" "${dest_app}"

xattr -dr com.apple.quarantine "${dest_app}" >/dev/null 2>&1 || true

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${dest_app}/Contents/Info.plist" 2>/dev/null || true)"
hotkey_json='{"carbonKeyCode":49,"carbonModifiers":4096}'

if [[ -n "${bundle_id}" ]]; then
  if [[ "${TWORELAY_FORCE_DEFAULT_HOTKEY:-0}" == "1" ]]; then
    defaults write "${bundle_id}" KeyboardShortcuts_relayListen -string "${hotkey_json}"
    echo "[2relay] preset hotkey: Control + Space (forced)"
  else
    if ! defaults read "${bundle_id}" KeyboardShortcuts_relayListen >/dev/null 2>&1; then
      defaults write "${bundle_id}" KeyboardShortcuts_relayListen -string "${hotkey_json}"
      echo "[2relay] preset hotkey: Control + Space"
    fi
  fi
fi

echo "[2relay] installed: ${dest_app}"

if [[ "${open_after_install}" == "1" ]]; then
  open -a "${dest_app}" || true
  echo "[2relay] launched"
fi

echo
echo "done."
echo "hotkey default is Control + Space."
