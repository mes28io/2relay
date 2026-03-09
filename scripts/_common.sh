#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: ${cmd}"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "missing required env var: ${name}"
}

bundle_value() {
  local app_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${app_path}/Contents/Info.plist"
}

sparkle_bin_dir() {
  local candidates=()
  local derived_data_glob

  if [[ -n "${SPARKLE_BIN_DIR:-}" ]]; then
    candidates+=("${SPARKLE_BIN_DIR}")
  fi

  candidates+=(
    "${REPO_ROOT}/SourcePackages/artifacts/sparkle/Sparkle/bin"
    "${REPO_ROOT}/.build/artifacts/sparkle/Sparkle/bin"
    "${REPO_ROOT}/.build/checkouts/Sparkle/bin"
    "${REPO_ROOT}/.swiftpm/xcode/package/artifacts/sparkle/Sparkle/bin"
  )

  shopt -s nullglob
  for derived_data_glob in "${HOME}"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
    candidates+=("${derived_data_glob}")
  done
  shopt -u nullglob

  local dir
  for dir in "${candidates[@]}"; do
    if [[ -d "${dir}" ]]; then
      echo "${dir}"
      return 0
    fi
  done

  die "could not find Sparkle bin directory. Set SPARKLE_BIN_DIR or open Sparkle package in Xcode first."
}

sparkle_tool() {
  local name="$1"
  local bin_dir
  bin_dir="$(sparkle_bin_dir)"
  local tool_path="${bin_dir}/${name}"
  [[ -x "${tool_path}" ]] || die "missing Sparkle tool: ${tool_path}"
  echo "${tool_path}"
}

normalize_marketing_version() {
  local raw_version="${1:-}"
  raw_version="${raw_version#v}"
  printf '%s\n' "${raw_version}"
}

default_marketing_version() {
  if [[ -n "${TWORELAY_MARKETING_VERSION:-}" ]]; then
    normalize_marketing_version "${TWORELAY_MARKETING_VERSION}"
    return 0
  fi

  local latest_tag
  latest_tag="$(git -C "${REPO_ROOT}" describe --tags --abbrev=0 2>/dev/null || true)"
  if [[ -n "${latest_tag}" ]]; then
    normalize_marketing_version "${latest_tag}"
    return 0
  fi

  printf '0.1.0\n'
}

default_build_version() {
  if [[ -n "${TWORELAY_BUILD_VERSION:-}" ]]; then
    printf '%s\n' "${TWORELAY_BUILD_VERSION}"
    return 0
  fi

  git -C "${REPO_ROOT}" rev-list --count HEAD 2>/dev/null || printf '1\n'
}

default_dist_dir() {
  echo "${REPO_ROOT}/dist"
}
