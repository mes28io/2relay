#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_cmd sed
require_cmd awk
require_env SPARKLE_PRIVATE_KEY_PATH

generate_keys_tool="$(sparkle_tool generate_keys)"
private_key_path="${SPARKLE_PRIVATE_KEY_PATH}"
mkdir -p "$(dirname "${private_key_path}")"

echo "[2relay] generating/loading Sparkle EdDSA keypair from keychain..."
output="$("${generate_keys_tool}" 2>&1 | tee /dev/stderr)"

public_key="$(printf '%s\n' "${output}" | sed -n 's|.*<string>\(.*\)</string>.*|\1|p' | head -n1)"
if [[ -z "${public_key}" ]]; then
  public_key="$(printf '%s\n' "${output}" | awk '/[A-Za-z0-9+\/=]{40,}/ {print $0}' | head -n1 | tr -d '[:space:]')"
fi
[[ -n "${public_key}" ]] || die "could not parse public key from generate_keys output"

echo "[2relay] exporting private key to ${private_key_path}..."
"${generate_keys_tool}" -x "${private_key_path}"
chmod 600 "${private_key_path}"

echo
echo "Public key (set this in Info.plist -> SUPublicEDKey):"
echo "${public_key}"
echo
echo "Private key exported to: ${private_key_path}"
echo "Do not commit this file."
