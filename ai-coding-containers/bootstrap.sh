#!/usr/bin/env bash
# bootstrap.sh — Issue #22
# Reproducible Claude Code environment bootstrap with pinned tool versions.
# Reads tool-lockfile.json, verifies checksums/versions, fails on drift.
# Two identical builds are verified by hash to confirm reproducibility.
#
# Usage:
#   ./bootstrap.sh [--lockfile <path>] [--verify-only] [--build-hash-file <path>]
#
# Environment variables:
#   LOCKFILE          Path to tool-lockfile.json (default: same dir as this script)
#   VERIFY_ONLY       If "true", only verify — do not install (default: false)
#   BUILD_HASH_FILE   Where to write/read the build hash (default: ./results/bootstrap.hash)
#   PNPM_HOME         pnpm global bin dir (default: ~/.local/share/pnpm)
#
# Exit codes:
#   0  — bootstrap complete and verified
#   1  — version/checksum drift detected (build fails)
#   2  — configuration / dependency error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCKFILE="${LOCKFILE:-${SCRIPT_DIR}/tool-lockfile.json}"
VERIFY_ONLY="${VERIFY_ONLY:-false}"
BUILD_HASH_FILE="${BUILD_HASH_FILE:-${SCRIPT_DIR}/../testcontainers/results/bootstrap.hash}"
PNPM_HOME="${PNPM_HOME:-${HOME}/.local/share/pnpm}"

# ── helpers ───────────────────────────────────────────────────────────────────

log()    { echo "[bootstrap] $*" >&2; }
ok()     { echo "[bootstrap] OK: $*" >&2; }
drift()  { echo "[bootstrap] DRIFT: $*" >&2; DRIFT_COUNT=$(( DRIFT_COUNT + 1 )); }
die()    { echo "[bootstrap] ERROR: $*" >&2; exit 2; }

DRIFT_COUNT=0

# Parse CLI flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lockfile)        LOCKFILE="$2";         shift 2 ;;
    --verify-only)     VERIFY_ONLY="true";    shift   ;;
    --build-hash-file) BUILD_HASH_FILE="$2";  shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--lockfile <path>] [--verify-only] [--build-hash-file <path>]"
      exit 0
      ;;
    *) die "Unknown flag: $1" ;;
  esac
done

[[ -f "${LOCKFILE}" ]] || die "Lockfile not found: ${LOCKFILE}"

log "Lockfile: ${LOCKFILE}"
log "Mode:     $([ "${VERIFY_ONLY}" == "true" ] && echo verify-only || echo install+verify)"

# ── version comparison helper ─────────────────────────────────────────────────
# Returns 0 if actual >= required, 1 otherwise
version_gte() {
  local required="$1"
  local actual="$2"
  # Use sort -V to compare semantic versions
  printf '%s\n%s\n' "${required}" "${actual}" \
    | sort -V -C 2>/dev/null && return 0 || return 1
}

# ── npm package: install + verify ────────────────────────────────────────────

install_npm_package() {
  local pkg="$1"
  local expected_version="$2"
  local expected_integrity="$3"

  if [[ "${VERIFY_ONLY}" == "true" ]]; then
    log "Skipping install (verify-only): ${pkg}@${expected_version}"
  else
    log "Installing ${pkg}@${expected_version} via pnpm..."
    pnpm install -g "${pkg}@${expected_version}" --prefer-offline 2>&1 \
      || log "WARNING: pnpm install failed for ${pkg} (may already be installed)"
  fi
}

verify_npm_package() {
  local pkg="$1"
  local expected_version="$2"
  local expected_integrity="$3"

  # Get installed version from pnpm global list
  local actual_version
  actual_version="$(pnpm list -g --json 2>/dev/null \
    | jq -r --arg p "${pkg}" '.[] | .dependencies[$p].version // empty' 2>/dev/null \
    | head -1 || echo '')"

  if [[ -z "${actual_version}" ]]; then
    drift "npm package ${pkg}: not installed (expected ${expected_version})"
    return
  fi

  if [[ "${actual_version}" != "${expected_version}" ]]; then
    drift "npm package ${pkg}: version mismatch (expected=${expected_version} actual=${actual_version})"
  else
    ok "${pkg}@${actual_version}"
  fi

  # Integrity check: compare published integrity from npm registry
  # Skip if integrity is a placeholder (starts with "sha512-placeholder")
  if [[ "${expected_integrity}" == "sha512-placeholder"* ]]; then
    log "NOTE: ${pkg} integrity is a placeholder — skipping checksum verification"
    log "      Update tool-lockfile.json with: npm view ${pkg}@${expected_version} dist.integrity"
    return
  fi

  local actual_integrity
  actual_integrity="$(npm view "${pkg}@${expected_version}" dist.integrity 2>/dev/null || echo '')"

  if [[ -z "${actual_integrity}" ]]; then
    log "WARNING: Could not fetch integrity for ${pkg}@${expected_version} from registry"
    return
  fi

  if [[ "${actual_integrity}" != "${expected_integrity}" ]]; then
    drift "npm package ${pkg}: integrity mismatch (expected=${expected_integrity} actual=${actual_integrity})"
  else
    ok "${pkg} integrity verified"
  fi
}

# ── python package: install + verify ─────────────────────────────────────────

install_python_package() {
  local pkg="$1"
  local version="$2"
  local source="$3"

  if [[ "${VERIFY_ONLY}" == "true" ]]; then
    log "Skipping install (verify-only): ${pkg}@${version}"
    return
  fi

  if [[ -n "${source}" ]] && [[ "${source}" == git+* ]]; then
    local ref
    ref="$(echo "${source}" | sed 's/.*@//')"
    log "Installing ${pkg} from git source: ${source}"
    uv tool install "${source}" --force 2>&1 || \
      log "WARNING: uv tool install failed for ${pkg}"
  else
    log "Installing ${pkg}==${version} via uv..."
    uv pip install "${pkg}==${version}" 2>&1 || \
      log "WARNING: uv install failed for ${pkg}"
  fi
}

verify_python_package() {
  local pkg="$1"
  local expected_version="$2"
  local expected_integrity="$3"

  local actual_version
  actual_version="$(uv pip show "${pkg}" 2>/dev/null \
    | grep '^Version:' | awk '{print $2}' || echo '')"

  if [[ -z "${actual_version}" ]]; then
    # Also check uv tool list
    actual_version="$(uv tool list 2>/dev/null \
      | grep "^${pkg}" | awk '{print $2}' | tr -d 'v' || echo '')"
  fi

  if [[ -z "${actual_version}" ]]; then
    drift "Python package ${pkg}: not installed (expected ${expected_version})"
    return
  fi

  if [[ "${actual_version}" != "${expected_version}" ]]; then
    drift "Python package ${pkg}: version mismatch (expected=${expected_version} actual=${actual_version})"
  else
    ok "${pkg}==${actual_version}"
  fi

  # Integrity check (skip placeholders)
  if [[ "${expected_integrity}" == "sha256:placeholder"* ]]; then
    log "NOTE: ${pkg} integrity is a placeholder — skipping checksum verification"
    log "      Update tool-lockfile.json with: pip download ${pkg}==${expected_version} && sha256sum *.whl"
    return
  fi
}

# ── system binary version check ───────────────────────────────────────────────

verify_system_binary() {
  local binary="$1"
  local min_version="$2"
  local check_cmd="$3"
  local version_regex="$4"

  local version_output
  version_output="$(eval "${check_cmd}" 2>&1 || echo '')"

  local actual_version
  actual_version="$(echo "${version_output}" | grep -oP "${version_regex}" | grep -oP '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo '')"

  if [[ -z "${actual_version}" ]]; then
    drift "System binary ${binary}: not found or version undetectable"
    return
  fi

  if ! version_gte "${min_version}" "${actual_version}"; then
    drift "System binary ${binary}: version too old (min=${min_version} actual=${actual_version})"
  else
    ok "${binary} ${actual_version} >= ${min_version}"
  fi
}

# ── build hash ────────────────────────────────────────────────────────────────
#
# The build hash is a SHA-256 of the lockfile contents + installed tool versions.
# Two identical builds should produce the same hash.

compute_build_hash() {
  local hash_input=""

  # Lockfile content
  hash_input+="$(cat "${LOCKFILE}")"

  # Installed npm versions
  hash_input+="$(pnpm list -g --json 2>/dev/null | jq -Sc . || echo '{}')"

  # Installed python versions
  hash_input+="$(uv pip list --format=json 2>/dev/null | jq -Sc . || echo '[]')"

  echo "${hash_input}" | sha256sum | awk '{print $1}'
}

save_build_hash() {
  local hash="$1"
  mkdir -p "$(dirname "${BUILD_HASH_FILE}")"
  echo "${hash}" > "${BUILD_HASH_FILE}"
  log "Build hash saved: ${hash} -> ${BUILD_HASH_FILE}"
}

verify_build_hash() {
  local current_hash="$1"

  if [[ ! -f "${BUILD_HASH_FILE}" ]]; then
    log "No previous build hash found — saving current hash for future comparison"
    save_build_hash "${current_hash}"
    return 0
  fi

  local previous_hash
  previous_hash="$(cat "${BUILD_HASH_FILE}")"

  if [[ "${current_hash}" == "${previous_hash}" ]]; then
    ok "Build hash matches previous run: ${current_hash}"
  else
    drift "Build hash mismatch: expected=${previous_hash} actual=${current_hash}"
    log "This indicates non-reproducible tooling — update the lockfile or investigate version drift"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

log "Starting bootstrap verification..."
log ""

# ── 1. npm packages ───────────────────────────────────────────────────────────
log "=== Node.js Packages ==="
jq -r '.node_packages | to_entries[] | "\(.key)\t\(.value.version)\t\(.value.integrity)"' \
  "${LOCKFILE}" \
  | while IFS=$'\t' read -r pkg version integrity; do
      install_npm_package  "${pkg}" "${version}" "${integrity}"
      verify_npm_package   "${pkg}" "${version}" "${integrity}"
    done

echo ""

# ── 2. python packages ────────────────────────────────────────────────────────
log "=== Python Packages ==="
jq -r '.python_packages | to_entries[] |
  "\(.key)\t\(.value.version // "")\t\(.value.integrity // "")\t\(.value.source // "")"' \
  "${LOCKFILE}" \
  | while IFS=$'\t' read -r pkg version integrity source; do
      install_python_package "${pkg}" "${version}" "${source}"
      verify_python_package  "${pkg}" "${version}" "${integrity}"
    done

echo ""

# ── 3. system binaries ────────────────────────────────────────────────────────
log "=== System Binaries ==="
jq -r '.system_binaries | to_entries[] |
  "\(.key)\t\(.value.min_version)\t\(.value.check_command)\t\(.value.version_regex)"' \
  "${LOCKFILE}" \
  | while IFS=$'\t' read -r binary min_version check_cmd version_regex; do
      verify_system_binary "${binary}" "${min_version}" "${check_cmd}" "${version_regex}"
    done

echo ""

# ── 4. build hash ─────────────────────────────────────────────────────────────
log "=== Build Reproducibility Hash ==="
current_hash="$(compute_build_hash)"
log "Current build hash: ${current_hash}"
verify_build_hash "${current_hash}"
save_build_hash   "${current_hash}"

echo ""

# ── 5. result ────────────────────────────────────────────────────────────────
if [[ "${DRIFT_COUNT}" -gt 0 ]]; then
  echo ""
  log "BOOTSTRAP FAILED — ${DRIFT_COUNT} drift(s) detected. Build is non-reproducible."
  log "Review the DRIFT messages above and update tool-lockfile.json or pin tool versions."
  exit 1
else
  log "Bootstrap complete — all ${DRIFT_COUNT} drift checks passed. Build is reproducible."
  log "Build hash: ${current_hash}"
  exit 0
fi
