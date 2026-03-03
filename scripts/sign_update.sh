#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_env SPARKLE_PRIVATE_KEY_PATH

artifact_path="${1:-}"
[[ -n "${artifact_path}" ]] || die "usage: $0 /abs/path/to/update.zip"
[[ -f "${artifact_path}" ]] || die "artifact not found: ${artifact_path}"
[[ -f "${SPARKLE_PRIVATE_KEY_PATH}" ]] || die "private key file not found: ${SPARKLE_PRIVATE_KEY_PATH}"

sign_tool="$(sparkle_tool sign_update)"
generate_keys_tool="$(sparkle_tool generate_keys)"

help_text="$("${sign_tool}" --help 2>&1 || true)"

if printf '%s\n' "${help_text}" | grep -q -- "--ed-key-file"; then
  output="$("${sign_tool}" --ed-key-file "${SPARKLE_PRIVATE_KEY_PATH}" "${artifact_path}")"
else
  # Fallback for older sign_update: import private key into keychain, then sign.
  "${generate_keys_tool}" -f "${SPARKLE_PRIVATE_KEY_PATH}" >/dev/null
  output="$("${sign_tool}" "${artifact_path}")"
fi

printf '%s\n' "${output}"
