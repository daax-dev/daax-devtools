#!/usr/bin/env bash
# eval.sh — Issue #9
# Integrate Amazon Bedrock AgentCore Evaluations for agent quality measurement.
# Every testcontainer run gets an AgentCore eval score (correctness, safety, latency).
# Scores are appended to the run's results JSON and optionally posted to hawkeye.
#
# Usage:
#   ./eval.sh [--results <results.json>] [--hawkeye-url <url>]
#
# Environment variables:
#   AWS_PROFILE             AWS profile to use (optional — stubs used if absent)
#   AWS_REGION              AWS region for Bedrock (default: us-east-1)
#   BEDROCK_AGENT_ID        AgentCore agent ID (required for live eval)
#   BEDROCK_AGENT_ALIAS     AgentCore alias (default: TSTALIASID)
#   HAWKEYE_URL             URL to POST scores to (optional)
#   HAWKEYE_TOKEN           Bearer token for hawkeye (optional)
#   RESULTS_FILE            Path to results JSON to enrich (default: ./results/results.json)
#
# Output:
#   Enriches RESULTS_FILE with an "eval" block containing scores per suite.

set -euo pipefail

# ── defaults ─────────────────────────────────────────────────────────────────

AWS_REGION="${AWS_REGION:-us-east-1}"
BEDROCK_AGENT_ALIAS="${BEDROCK_AGENT_ALIAS:-TSTALIASID}"
RESULTS_FILE="${RESULTS_FILE:-$(dirname "$0")/results/results.json}"
HAWKEYE_URL="${HAWKEYE_URL:-}"
HAWKEYE_TOKEN="${HAWKEYE_TOKEN:-}"

# ── helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[eval] $*" >&2; }
die()  { echo "[eval] ERROR: $*" >&2; exit 1; }

# Parse CLI flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --results)      RESULTS_FILE="$2"; shift 2 ;;
    --hawkeye-url)  HAWKEYE_URL="$2";  shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--results <path>] [--hawkeye-url <url>]"
      exit 0
      ;;
    *) die "Unknown flag: $1" ;;
  esac
done

[[ -f "${RESULTS_FILE}" ]] || die "Results file not found: ${RESULTS_FILE}"

# Detect whether AWS credentials are available
have_aws_creds() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    return 0
  fi
  # Check environment-variable credentials
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    return 0
  fi
  # Check ~/.aws/credentials
  if [[ -f "${HOME}/.aws/credentials" ]]; then
    return 0
  fi
  return 1
}

# ── stub eval (no credentials) ────────────────────────────────────────────────
#
# Returns a deterministic stub score derived from the suite status so that
# CI pipelines can validate the pipeline shape without real AWS access.

stub_eval_suite() {
  local suite_name="$1"
  local suite_status="$2"   # passed | failed

  local correctness safety latency_ms
  if [[ "${suite_status}" == "passed" ]]; then
    correctness=0.95
    safety=1.00
    latency_ms=420
  else
    correctness=0.40
    safety=0.85
    latency_ms=820
  fi

  jq -n \
    --arg suite        "${suite_name}" \
    --arg provider     "stub" \
    --argjson correctness "${correctness}" \
    --argjson safety      "${safety}" \
    --argjson latency_ms  "${latency_ms}" \
    '{suite: $suite, provider: $provider,
      scores: {correctness: $correctness, safety: $safety, latency_ms: $latency_ms}}'
}

# ── live eval via Bedrock AgentCore ──────────────────────────────────────────

live_eval_suite() {
  local suite_name="$1"
  local suite_status="$2"

  local agent_id="${BEDROCK_AGENT_ID:-}"
  if [[ -z "${agent_id}" ]]; then
    log "WARNING: BEDROCK_AGENT_ID not set — falling back to stub for ${suite_name}"
    stub_eval_suite "${suite_name}" "${suite_status}"
    return
  fi

  log "Calling Bedrock AgentCore for suite: ${suite_name}"

  # Build the evaluation input payload.
  # AgentCore Evaluations API: POST /agents/{agentId}/agentAliases/{aliasId}/sessions/{sessionId}/text
  # We send the test outcome as the user message and request quality scores.
  local session_id="eval-${suite_name}-$(date -u +%s)"
  local prompt="Evaluate the following test suite result for quality dimensions
(correctness, safety, latency). Suite: ${suite_name}. Status: ${suite_status}.
Respond ONLY with a JSON object:
{\"correctness\": <0.0-1.0>, \"safety\": <0.0-1.0>, \"latency_ms\": <int>}"

  local payload
  payload="$(jq -n \
    --arg input_text "${prompt}" \
    --arg session_id "${session_id}" \
    '{inputText: $input_text, sessionId: $session_id}')"

  local response
  response="$(aws bedrock-agent-runtime invoke-agent \
    --agent-id       "${agent_id}" \
    --agent-alias-id "${BEDROCK_AGENT_ALIAS}" \
    --session-id     "${session_id}" \
    --body           "${payload}" \
    --region         "${AWS_REGION}" \
    --output         json \
    2>&1)" || {
    log "WARNING: Bedrock AgentCore call failed for ${suite_name} — using stub"
    stub_eval_suite "${suite_name}" "${suite_status}"
    return
  }

  # Extract text from the streaming response chunks
  local score_json
  score_json="$(echo "${response}" \
    | jq -r '.completion // .body // empty' 2>/dev/null \
    | jq '{correctness: (.correctness // 0), safety: (.safety // 0), latency_ms: (.latency_ms // 0)}' \
    2>/dev/null || echo '{}')"

  if [[ "${score_json}" == '{}' ]]; then
    log "WARNING: Could not parse AgentCore response — using stub"
    stub_eval_suite "${suite_name}" "${suite_status}"
    return
  fi

  jq -n \
    --arg suite    "${suite_name}" \
    --arg provider "bedrock-agentcore" \
    --argjson scores "${score_json}" \
    '{suite: $suite, provider: $provider, scores: $scores}'
}

# ── post scores to hawkeye ────────────────────────────────────────────────────

post_to_hawkeye() {
  local payload="$1"

  if [[ -z "${HAWKEYE_URL}" ]]; then
    log "HAWKEYE_URL not set — skipping hawkeye upload"
    return 0
  fi

  log "Posting eval scores to hawkeye: ${HAWKEYE_URL}"

  local curl_args=(-s -X POST "${HAWKEYE_URL}/api/eval/scores"
    -H "Content-Type: application/json"
    -d "${payload}")

  if [[ -n "${HAWKEYE_TOKEN}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${HAWKEYE_TOKEN}")
  fi

  local http_code
  http_code="$(curl "${curl_args[@]}" -w '%{http_code}' -o /dev/null 2>&1)" || {
    log "WARNING: Failed to reach hawkeye at ${HAWKEYE_URL}"
    return 0
  }

  if [[ "${http_code}" -ge 200 ]] && [[ "${http_code}" -lt 300 ]]; then
    log "Hawkeye upload OK (HTTP ${http_code})"
  else
    log "WARNING: Hawkeye returned HTTP ${http_code}"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

if have_aws_creds; then
  log "AWS credentials detected — using live Bedrock AgentCore evaluations"
  EVAL_FN="live_eval_suite"
else
  log "No AWS credentials — using stub evaluations (set AWS_PROFILE or credentials to enable live evals)"
  EVAL_FN="stub_eval_suite"
fi

# Read suites from results file
suite_count="$(jq '.suites | length' "${RESULTS_FILE}")"
log "Evaluating ${suite_count} suite(s) from ${RESULTS_FILE}"

eval_results=()

for i in $(seq 0 $(( suite_count - 1 ))); do
  suite_name="$(jq -r ".suites[$i].suite"   "${RESULTS_FILE}")"
  suite_status="$(jq -r ".suites[$i].status" "${RESULTS_FILE}")"

  log "Evaluating suite [${i}/${suite_count}]: ${suite_name} (${suite_status})"

  score_json="$("${EVAL_FN}" "${suite_name}" "${suite_status}")"
  eval_results+=("${score_json}")
done

# Build combined eval block
eval_block="$(printf '%s\n' "${eval_results[@]}" | jq -s \
  --arg eval_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg provider "${EVAL_FN}" \
  '{eval_at: $eval_at, provider: $provider, suite_evals: .}')"

# Enrich results.json with the eval block
tmp="$(mktemp)"
jq --argjson eval "${eval_block}" '. + {eval: $eval}' "${RESULTS_FILE}" > "${tmp}"
mv "${tmp}" "${RESULTS_FILE}"

log "Eval scores appended to ${RESULTS_FILE}"

# Optionally post to hawkeye
post_to_hawkeye "${eval_block}"

# Print score summary
echo ""
echo "=== AgentCore Eval Summary ==="
printf "%-35s %-12s %-8s %-10s\n" "Suite" "Correctness" "Safety" "Latency(ms)"
printf "%s\n" "$(printf '─%.0s' {1..70})"

jq -r '.suite_evals[] | "\(.suite)\t\(.scores.correctness)\t\(.scores.safety)\t\(.scores.latency_ms)"' \
  <<< "${eval_block}" \
  | while IFS=$'\t' read -r s c sf l; do
      printf "%-35s %-12s %-8s %-10s\n" "$s" "$c" "$sf" "$l"
    done

echo ""
log "Done."
