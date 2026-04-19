#!/usr/bin/env bash
# run-isolated.sh — Issue #8
# Run each test suite in a dedicated nanofuse microVM (or Docker fallback).
# Suites execute in parallel; results are collected after all complete.
#
# Usage:
#   ./run-isolated.sh <suite-dir> [<suite-dir> ...]
#
# Environment variables:
#   NANOFUSE_BIN        Path to nanofuse binary (default: nanofuse)
#   RESULTS_DIR         Where to write per-suite result JSON (default: ./results)
#   DOCKER_IMAGE        Fallback Docker image (default: jpoley/daax-agents:latest)
#   PARALLEL_LIMIT      Max concurrent suites (default: number of suites)
#
# Output:
#   <RESULTS_DIR>/<suite-name>.json  — per-suite result
#   <RESULTS_DIR>/results.json       — aggregated results (input for report.sh)

set -euo pipefail

NANOFUSE_BIN="${NANOFUSE_BIN:-nanofuse}"
RESULTS_DIR="${RESULTS_DIR:-$(dirname "$0")/results}"
DOCKER_IMAGE="${DOCKER_IMAGE:-jpoley/daax-agents:latest}"

# ── helpers ──────────────────────────────────────────────────────────────────

log()  { echo "[run-isolated] $*" >&2; }
die()  { echo "[run-isolated] ERROR: $*" >&2; exit 1; }

usage() {
  echo "Usage: $0 <suite-dir> [<suite-dir> ...]" >&2
  exit 1
}

have_nanofuse() {
  command -v "$NANOFUSE_BIN" >/dev/null 2>&1
}

# Run a single suite inside a nanofuse microVM.
# Writes result JSON to $RESULTS_DIR/<suite-name>.json.
run_in_nanofuse() {
  local suite_dir="$1"
  local suite_name
  suite_name="$(basename "$suite_dir")"
  local out_file="${RESULTS_DIR}/${suite_name}.json"
  local start_ts
  start_ts="$(date -u +%s)"

  log "Starting nanofuse microVM for suite: ${suite_name}"

  # nanofuse creates an ephemeral Firecracker microVM, mounts the suite dir
  # read-only, runs the suite entrypoint, captures exit code and stdout/stderr.
  local tmp_log
  tmp_log="$(mktemp)"

  local exit_code=0
  "$NANOFUSE_BIN" run \
    --ephemeral \
    --mount "${suite_dir}:/suite:ro" \
    --env "SUITE_NAME=${suite_name}" \
    --output-json "${out_file}" \
    -- bash /suite/run.sh 2>"${tmp_log}" || exit_code=$?

  local end_ts
  end_ts="$(date -u +%s)"
  local duration=$(( end_ts - start_ts ))

  # If nanofuse already wrote a result JSON we enrich it; otherwise we create one.
  if [[ -f "${out_file}" ]]; then
    local tmp
    tmp="$(mktemp)"
    jq --arg suite  "${suite_name}" \
       --arg status "$([ "${exit_code}" -eq 0 ] && echo passed || echo failed)" \
       --argjson exit_code "${exit_code}" \
       --argjson duration "${duration}" \
       --arg runtime "nanofuse" \
       '. + {suite: $suite, status: $status, exit_code: $exit_code,
              duration_s: $duration, runtime: $runtime}' \
       "${out_file}" > "${tmp}"
    mv "${tmp}" "${out_file}"
  else
    # nanofuse did not write a JSON — synthesise one from stderr log
    local stderr_content
    stderr_content="$(cat "${tmp_log}" 2>/dev/null || true)"
    jq -n \
      --arg suite       "${suite_name}" \
      --arg status      "$([ "${exit_code}" -eq 0 ] && echo passed || echo failed)" \
      --argjson exit_code "${exit_code}" \
      --argjson duration "${duration}" \
      --arg runtime     "nanofuse" \
      --arg stderr      "${stderr_content}" \
      '{suite: $suite, status: $status, exit_code: $exit_code,
        duration_s: $duration, runtime: $runtime, stderr: $stderr}' \
      > "${out_file}"
  fi

  rm -f "${tmp_log}"
  log "Suite ${suite_name}: exit_code=${exit_code} duration=${duration}s"
  return "${exit_code}"
}

# Run a single suite inside a Docker container (fallback when nanofuse absent).
run_in_docker() {
  local suite_dir="$1"
  local suite_name
  suite_name="$(basename "$suite_dir")"
  local out_file="${RESULTS_DIR}/${suite_name}.json"
  local start_ts
  start_ts="$(date -u +%s)"

  log "Starting Docker container for suite: ${suite_name} (nanofuse not available)"

  local tmp_log
  tmp_log="$(mktemp)"

  local exit_code=0
  docker run --rm \
    --name "tc-${suite_name}-$$" \
    -v "${suite_dir}:/suite:ro" \
    -e "SUITE_NAME=${suite_name}" \
    "${DOCKER_IMAGE}" \
    bash /suite/run.sh > "${tmp_log}" 2>&1 || exit_code=$?

  local end_ts
  end_ts="$(date -u +%s)"
  local duration=$(( end_ts - start_ts ))

  local output
  output="$(cat "${tmp_log}" 2>/dev/null || true)"

  jq -n \
    --arg suite       "${suite_name}" \
    --arg status      "$([ "${exit_code}" -eq 0 ] && echo passed || echo failed)" \
    --argjson exit_code "${exit_code}" \
    --argjson duration "${duration}" \
    --arg runtime     "docker" \
    --arg output      "${output}" \
    '{suite: $suite, status: $status, exit_code: $exit_code,
      duration_s: $duration, runtime: $runtime, output: $output}' \
    > "${out_file}"

  rm -f "${tmp_log}"
  log "Suite ${suite_name}: exit_code=${exit_code} duration=${duration}s"
  return "${exit_code}"
}

# Dispatch a single suite to the appropriate runtime.
run_suite() {
  local suite_dir="$1"
  local suite_name
  suite_name="$(basename "$suite_dir")"

  if [[ ! -d "${suite_dir}" ]]; then
    log "WARNING: ${suite_dir} is not a directory — skipping"
    return 0
  fi

  if [[ ! -f "${suite_dir}/run.sh" ]]; then
    log "WARNING: ${suite_dir}/run.sh not found — skipping ${suite_name}"
    return 0
  fi

  if have_nanofuse; then
    run_in_nanofuse "${suite_dir}"
  else
    run_in_docker   "${suite_dir}"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage

mkdir -p "${RESULTS_DIR}"

if have_nanofuse; then
  log "Runtime: nanofuse ($(command -v "$NANOFUSE_BIN"))"
else
  log "Runtime: docker (nanofuse not found — falling back)"
  command -v docker >/dev/null 2>&1 || die "Neither nanofuse nor docker found in PATH"
fi

# Run all suites in parallel, capturing PIDs
declare -A PIDS   # suite_name -> PID

for suite in "$@"; do
  suite_name="$(basename "$suite")"
  log "Launching suite: ${suite_name}"
  run_suite "$suite" &
  PIDS["${suite_name}"]=$!
done

# Wait for all and collect exit codes
overall_exit=0
declare -A STATUSES

for suite_name in "${!PIDS[@]}"; do
  pid="${PIDS[$suite_name]}"
  if wait "$pid"; then
    STATUSES["${suite_name}"]="passed"
  else
    STATUSES["${suite_name}"]="failed"
    overall_exit=1
  fi
done

# Aggregate all per-suite JSON files into a single results.json
log "Aggregating results..."
aggregate="${RESULTS_DIR}/results.json"

# Build a jq array from every suite JSON present
result_files=()
for suite in "$@"; do
  suite_name="$(basename "$suite")"
  f="${RESULTS_DIR}/${suite_name}.json"
  [[ -f "$f" ]] && result_files+=("$f")
done

if [[ ${#result_files[@]} -gt 0 ]]; then
  jq -s \
    --arg run_at   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg overall  "$([ "${overall_exit}" -eq 0 ] && echo passed || echo failed)" \
    '{run_at: $run_at, overall: $overall, suites: .}' \
    "${result_files[@]}" > "${aggregate}"
else
  jq -n \
    --arg run_at  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg overall "$([ "${overall_exit}" -eq 0 ] && echo passed || echo failed)" \
    '{run_at: $run_at, overall: $overall, suites: []}' \
    > "${aggregate}"
fi

log "Results written to ${aggregate}"

# Print summary table
echo ""
echo "=== Test Suite Summary ==="
printf "%-40s %s\n" "Suite" "Status"
printf "%s\n" "$(printf '─%.0s' {1..50})"
for suite_name in "${!STATUSES[@]}"; do
  printf "%-40s %s\n" "${suite_name}" "${STATUSES[$suite_name]}"
done
echo ""

if [[ "${overall_exit}" -ne 0 ]]; then
  log "One or more suites FAILED"
fi

exit "${overall_exit}"
