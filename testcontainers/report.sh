#!/usr/bin/env bash
# report.sh — Issue #10
# Normalize test results to shared JSON schema, diff vs previous run,
# and output a structured JSON results file + markdown report.
#
# Usage:
#   ./report.sh [--results <results.json>] [--prev <results.prev.json>] [--out-dir <dir>]
#
# Environment variables:
#   RESULTS_FILE    Input results JSON (default: ./results/results.json)
#   PREV_FILE       Previous run results for regression diff (default: ./results/results.prev.json)
#   OUT_DIR         Output directory for report files (default: ./results)
#
# Output:
#   <OUT_DIR>/results.normalized.json  — normalized results (canonical schema)
#   <OUT_DIR>/report.md               — human-readable markdown report
#   <OUT_DIR>/results.prev.json       — current results saved as prev for next run

set -euo pipefail

# ── defaults ─────────────────────────────────────────────────────────────────

RESULTS_FILE="${RESULTS_FILE:-$(dirname "$0")/results/results.json}"
PREV_FILE="${PREV_FILE:-$(dirname "$0")/results/results.prev.json}"
OUT_DIR="${OUT_DIR:-$(dirname "$0")/results}"

# ── helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[report] $*" >&2; }
die()  { echo "[report] ERROR: $*" >&2; exit 1; }

# Parse CLI flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --results) RESULTS_FILE="$2"; shift 2 ;;
    --prev)    PREV_FILE="$2";    shift 2 ;;
    --out-dir) OUT_DIR="$2";      shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--results <path>] [--prev <path>] [--out-dir <dir>]"
      exit 0
      ;;
    *) die "Unknown flag: $1" ;;
  esac
done

[[ -f "${RESULTS_FILE}" ]] || die "Results file not found: ${RESULTS_FILE}"
mkdir -p "${OUT_DIR}"

NORMALIZED="${OUT_DIR}/results.normalized.json"
REPORT_MD="${OUT_DIR}/report.md"

# ── schema normalisation ─────────────────────────────────────────────────────
#
# Canonical suite record schema:
# {
#   "suite":       string,
#   "status":      "passed" | "failed" | "skipped" | "error",
#   "exit_code":   int,
#   "duration_s":  number,
#   "runtime":     "nanofuse" | "docker" | "unknown",
#   "correctness": number | null,   (from eval.sh if available)
#   "safety":      number | null,
#   "latency_ms":  int | null
# }

log "Normalising results from ${RESULTS_FILE}"

jq '
  # Merge eval scores into suite records if present
  def enrich_with_eval(eval_map):
    if eval_map then
      .suite as $s
      | eval_map[$s] as $e
      | . + {
          correctness: ($e.scores.correctness // null),
          safety:      ($e.scores.safety      // null),
          latency_ms:  ($e.scores.latency_ms  // null)
        }
    else
      . + {correctness: null, safety: null, latency_ms: null}
    end;

  # Build a lookup map from eval data
  (.eval.suite_evals // []) as $eval_list
  | ([$eval_list[] | {key: .suite, value: .}] | from_entries) as $eval_map

  | {
      schema_version: "1.0",
      run_at:         (.run_at  // "unknown"),
      overall:        (.overall // "unknown"),
      suites: [
        .suites[] | {
          suite:      (.suite      // "unknown"),
          status:     (.status     // "unknown"),
          exit_code:  (.exit_code  // -1),
          duration_s: (.duration_s // 0),
          runtime:    (.runtime    // "unknown")
        } | enrich_with_eval($eval_map)
      ],
      eval: (.eval // null)
    }
' "${RESULTS_FILE}" > "${NORMALIZED}"

log "Normalized schema written to ${NORMALIZED}"

# ── regression diff ──────────────────────────────────────────────────────────

log "Computing diff vs previous run..."

REGRESSIONS=()
NEW_FAILURES=()
FIXED=()
NEW_SUITES=()

if [[ -f "${PREV_FILE}" ]]; then
  # Build lookup: suite_name -> status from previous run
  prev_statuses="$(jq -r '.suites[] | "\(.suite)\t\(.status)"' "${PREV_FILE}" 2>/dev/null || echo '')"
  curr_statuses="$(jq -r '.suites[] | "\(.suite)\t\(.status)"' "${NORMALIZED}")"

  declare -A PREV_MAP
  while IFS=$'\t' read -r name status; do
    [[ -z "${name}" ]] && continue
    PREV_MAP["${name}"]="${status}"
  done <<< "${prev_statuses}"

  while IFS=$'\t' read -r name status; do
    [[ -z "${name}" ]] && continue
    prev_status="${PREV_MAP[${name}]:-}"

    if [[ -z "${prev_status}" ]]; then
      NEW_SUITES+=("${name}")
    elif [[ "${prev_status}" == "passed" ]] && [[ "${status}" != "passed" ]]; then
      REGRESSIONS+=("${name}")
    elif [[ "${prev_status}" != "passed" ]] && [[ "${status}" == "passed" ]]; then
      FIXED+=("${name}")
    elif [[ "${status}" != "passed" ]]; then
      NEW_FAILURES+=("${name}")
    fi
  done <<< "${curr_statuses}"

  log "Regressions: ${#REGRESSIONS[@]}  Fixed: ${#FIXED[@]}  New failures: ${#NEW_FAILURES[@]}  New suites: ${#NEW_SUITES[@]}"
else
  log "No previous results found at ${PREV_FILE} — skipping diff"
fi

# ── generate markdown report ─────────────────────────────────────────────────

log "Generating markdown report..."

run_at="$(jq -r '.run_at'  "${NORMALIZED}")"
overall="$(jq -r '.overall' "${NORMALIZED}")"
total="$(jq '.suites | length' "${NORMALIZED}")"
passed="$(jq '[.suites[] | select(.status=="passed")] | length' "${NORMALIZED}")"
failed="$(jq '[.suites[] | select(.status!="passed")] | length' "${NORMALIZED}")"

overall_icon="✅"
[[ "${overall}" != "passed" ]] && overall_icon="❌"

{
  echo "# Test Run Report"
  echo ""
  echo "**Run at:** ${run_at}  "
  echo "**Overall:** ${overall_icon} ${overall}  "
  echo "**Suites:** ${total} total / ${passed} passed / ${failed} failed"
  echo ""

  # ── regression section ────────────────────────────────────────────────────
  if [[ -f "${PREV_FILE}" ]]; then
    echo "## Regression Diff"
    echo ""

    if [[ ${#REGRESSIONS[@]} -gt 0 ]]; then
      echo "### ⚠️ Regressions (was passing, now failing)"
      for s in "${REGRESSIONS[@]}"; do
        echo "- \`${s}\`"
      done
      echo ""
    fi

    if [[ ${#FIXED[@]} -gt 0 ]]; then
      echo "### 🎉 Fixed (was failing, now passing)"
      for s in "${FIXED[@]}"; do
        echo "- \`${s}\`"
      done
      echo ""
    fi

    if [[ ${#NEW_FAILURES[@]} -gt 0 ]]; then
      echo "### 🔴 Persistent Failures"
      for s in "${NEW_FAILURES[@]}"; do
        echo "- \`${s}\`"
      done
      echo ""
    fi

    if [[ ${#NEW_SUITES[@]} -gt 0 ]]; then
      echo "### 🆕 New Suites"
      for s in "${NEW_SUITES[@]}"; do
        echo "- \`${s}\`"
      done
      echo ""
    fi

    if [[ ${#REGRESSIONS[@]} -eq 0 ]] && [[ ${#NEW_FAILURES[@]} -eq 0 ]]; then
      echo "_No regressions detected._"
      echo ""
    fi
  else
    echo "## Regression Diff"
    echo ""
    echo "_No previous run found — diff not available._"
    echo ""
  fi

  # ── suite table ───────────────────────────────────────────────────────────
  echo "## Suite Results"
  echo ""
  echo "| Suite | Status | Runtime | Duration (s) | Correctness | Safety | Latency (ms) |"
  echo "|-------|--------|---------|-------------|-------------|--------|--------------|"

  jq -r '.suites[] |
    [
      .suite,
      (if .status == "passed" then "✅ passed" else "❌ " + .status end),
      .runtime,
      (.duration_s | tostring),
      (.correctness | if . == null then "—" else tostring end),
      (.safety      | if . == null then "—" else tostring end),
      (.latency_ms  | if . == null then "—" else tostring end)
    ] | "| " + join(" | ") + " |"
  ' "${NORMALIZED}"

  echo ""

  # ── eval summary (if present) ─────────────────────────────────────────────
  eval_present="$(jq '.eval != null' "${NORMALIZED}")"
  if [[ "${eval_present}" == "true" ]]; then
    eval_provider="$(jq -r '.eval.provider // "unknown"' "${NORMALIZED}")"
    eval_at="$(jq -r '.eval.eval_at // "unknown"' "${NORMALIZED}")"
    echo "## AgentCore Eval Scores"
    echo ""
    echo "**Provider:** ${eval_provider}  "
    echo "**Evaluated at:** ${eval_at}"
    echo ""
    echo "_Scores per suite are shown in the Suite Results table above._"
    echo ""
  fi

  # ── footer ────────────────────────────────────────────────────────────────
  echo "---"
  echo ""
  echo "_Generated by \`testcontainers/report.sh\` — daax-devtools_"
} > "${REPORT_MD}"

log "Markdown report written to ${REPORT_MD}"

# ── save current as prev for next run ────────────────────────────────────────

cp "${NORMALIZED}" "${PREV_FILE}"
log "Saved current results as ${PREV_FILE} (for next run diff)"

# ── print report to stdout ───────────────────────────────────────────────────

echo ""
cat "${REPORT_MD}"

exit 0
