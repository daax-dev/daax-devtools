#!/usr/bin/env bash
# enforce-permissions.sh — Issue #21
# Validate a proposed session tool call against the per-session tool allowlist.
# Session creators may only narrow the default allowlist, never expand it.
# hawkeye is notified of every violation.
#
# Usage:
#   ./enforce-permissions.sh --session-id <id> --tool <tool> [--command <cmd>]
#                            [--path <path>] [--var <env-var>]
#
# Exit codes:
#   0  — tool call is permitted
#   1  — tool call is denied (violation logged)
#   2  — usage / configuration error
#
# Environment variables:
#   DEFAULT_PERMISSIONS     Path to base permissions.json (default: same dir as this script)
#   SESSIONS_DIR            Session state directory (default: /tmp/daax-sessions)
#   HAWKEYE_URL             Hawkeye endpoint for violation events (optional)
#   HAWKEYE_TOKEN           Bearer token for hawkeye (optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PERMISSIONS="${DEFAULT_PERMISSIONS:-${SCRIPT_DIR}/permissions.json}"
SESSIONS_DIR="${SESSIONS_DIR:-/tmp/daax-sessions}"
HAWKEYE_URL="${HAWKEYE_URL:-}"
HAWKEYE_TOKEN="${HAWKEYE_TOKEN:-}"

# ── helpers ───────────────────────────────────────────────────────────────────

log()      { echo "[enforce-permissions] $*" >&2; }
deny_msg() { echo "[enforce-permissions] DENIED: $*" >&2; }
die()      { echo "[enforce-permissions] ERROR: $*" >&2; exit 2; }

usage() {
  cat >&2 <<EOF
Usage:
  $0 --session-id <id> --tool <tool> [--command <cmd>] [--path <path>] [--var <env-var>]

Flags:
  --session-id  Session ID (required)
  --tool        Tool name being invoked (e.g. Bash, Read, WebFetch)
  --command     Shell command string (for Bash tool)
  --path        File system path (for Read/Write/Edit)
  --var         Environment variable name (for env access)
EOF
  exit 2
}

# ── arg parsing ────────────────────────────────────────────────────────────────

SESSION_ID=""
TOOL=""
COMMAND=""
PATH_ARG=""
VAR_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --tool)       TOOL="$2";       shift 2 ;;
    --command)    COMMAND="$2";    shift 2 ;;
    --path)       PATH_ARG="$2";   shift 2 ;;
    --var)        VAR_ARG="$2";    shift 2 ;;
    --help|-h)    usage ;;
    *)            die "Unknown flag: $1" ;;
  esac
done

[[ -z "${SESSION_ID}" ]] && die "--session-id is required"
[[ -z "${TOOL}"       ]] && die "--tool is required"

# ── load effective permissions ────────────────────────────────────────────────
#
# Effective = default allowlist narrowed by any session-level overrides.
# Session overrides may only set fields to false / restrict lists, never
# re-enable something that the default has set to false.

[[ -f "${DEFAULT_PERMISSIONS}" ]] || die "Default permissions file not found: ${DEFAULT_PERMISSIONS}"

SESSION_PERMISSIONS="${SESSIONS_DIR}/${SESSION_ID}/permissions.json"

if [[ -f "${SESSION_PERMISSIONS}" ]]; then
  # Merge: for boolean fields, effective = default AND session
  # For list fields (allowed_commands, denied_commands, allowed_hosts),
  # effective allowed = intersection; effective denied = union.
  EFFECTIVE="$(jq -s '
    .[0] as $d | .[1] as $s |
    {
      allowlist: {
        filesystem: {
          read:   ($d.allowlist.filesystem.read   and ($s.allowlist.filesystem.read   // true)),
          write:  ($d.allowlist.filesystem.write  and ($s.allowlist.filesystem.write  // true)),
          delete: ($d.allowlist.filesystem.delete and ($s.allowlist.filesystem.delete // false)),
          paths: {
            allowed: ($d.allowlist.filesystem.paths.allowed),
            denied:  ($d.allowlist.filesystem.paths.denied + ($s.allowlist.filesystem.paths.denied // []) | unique)
          }
        },
        network: {
          outbound:      ($d.allowlist.network.outbound and ($s.allowlist.network.outbound // false)),
          inbound:       ($d.allowlist.network.inbound  and ($s.allowlist.network.inbound  // false)),
          allowed_hosts: ([$d.allowlist.network.allowed_hosts[], ($s.allowlist.network.allowed_hosts // [])[] ] | unique)
        },
        processes: {
          exec: ($d.allowlist.processes.exec and ($s.allowlist.processes.exec // true)),
          allowed_commands: [
            $d.allowlist.processes.allowed_commands[] |
            . as $c |
            if (($s.allowlist.processes.denied_commands // []) | index($c)) != null then empty
            else $c end
          ],
          denied_commands: ($d.allowlist.processes.denied_commands + ($s.allowlist.processes.denied_commands // []) | unique)
        },
        environment: {
          read:  ($d.allowlist.environment.read  and ($s.allowlist.environment.read  // true)),
          write: ($d.allowlist.environment.write and ($s.allowlist.environment.write // true)),
          denied_vars: ($d.allowlist.environment.denied_vars + ($s.allowlist.environment.denied_vars // []) | unique)
        },
        tools: (
          $d.allowlist.tools |
          to_entries |
          map(
            .key as $k |
            .value as $dv |
            ($s.allowlist.tools[$k] // $dv) as $sv |
            {key: $k, value: (if ($dv | type) == "boolean" then ($dv and $sv) else $dv end)}
          ) |
          from_entries
        )
      },
      enforcement: $d.enforcement
    }
  ' "${DEFAULT_PERMISSIONS}" "${SESSION_PERMISSIONS}")"
else
  EFFECTIVE="$(cat "${DEFAULT_PERMISSIONS}")"
fi

# ── hawkeye violation reporter ────────────────────────────────────────────────

report_violation() {
  local reason="$1"

  local payload
  payload="$(jq -n \
    --arg session_id "${SESSION_ID}" \
    --arg tool       "${TOOL}" \
    --arg command    "${COMMAND}" \
    --arg path       "${PATH_ARG}" \
    --arg var        "${VAR_ARG}" \
    --arg reason     "${reason}" \
    --arg ts         "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{event: "permission.violation",
      session_id: $session_id,
      timestamp: $ts,
      tool: $tool,
      command: $command,
      path: $path,
      var: $var,
      reason: $reason}')"

  deny_msg "${reason}"

  if [[ -z "${HAWKEYE_URL}" ]]; then
    log "HAWKEYE_URL not set — violation not forwarded"
    return 0
  fi

  local curl_args=(-s -X POST "${HAWKEYE_URL}/api/violations"
    -H "Content-Type: application/json"
    -d "${payload}")
  [[ -n "${HAWKEYE_TOKEN}" ]] && curl_args+=(-H "Authorization: Bearer ${HAWKEYE_TOKEN}")

  curl "${curl_args[@]}" -o /dev/null 2>&1 || log "WARNING: Could not reach hawkeye"
}

# ── enforcement checks ────────────────────────────────────────────────────────

check_tool_allowed() {
  local tool="$1"
  local allowed
  allowed="$(echo "${EFFECTIVE}" | jq -r --arg t "${tool}" \
    '.allowlist.tools[$t] // false')"
  if [[ "${allowed}" != "true" ]]; then
    report_violation "Tool '${tool}' is not in the session allowlist"
    exit 1
  fi
}

check_command_allowed() {
  local cmd="$1"
  if [[ -z "${cmd}" ]]; then return 0; fi

  # Extract the base command (first token)
  local base_cmd
  base_cmd="$(echo "${cmd}" | awk '{print $1}' | xargs basename 2>/dev/null || echo "${cmd}")"

  # Check deny list first
  local denied
  denied="$(echo "${EFFECTIVE}" | jq -r --arg c "${base_cmd}" \
    '.allowlist.processes.denied_commands | index($c) != null')"
  if [[ "${denied}" == "true" ]]; then
    report_violation "Command '${base_cmd}' is on the denied_commands list"
    exit 1
  fi

  # Check allow list
  local allowed
  allowed="$(echo "${EFFECTIVE}" | jq -r --arg c "${base_cmd}" \
    '.allowlist.processes.allowed_commands | index($c) != null')"
  if [[ "${allowed}" != "true" ]]; then
    report_violation "Command '${base_cmd}' is not in the allowed_commands list"
    exit 1
  fi
}

check_path_allowed() {
  local path="$1"
  if [[ -z "${path}" ]]; then return 0; fi

  # Check allowed prefixes
  local allowed_paths
  allowed_paths="$(echo "${EFFECTIVE}" | jq -r '.allowlist.filesystem.paths.allowed[]')"
  local path_ok=false
  while IFS= read -r allowed_prefix; do
    [[ -z "${allowed_prefix}" ]] && continue
    if [[ "${path}" == "${allowed_prefix}"* ]]; then
      path_ok=true
      break
    fi
  done <<< "${allowed_paths}"

  if [[ "${path_ok}" != "true" ]]; then
    report_violation "Path '${path}' is outside allowed paths"
    exit 1
  fi

  # Check denied prefixes
  local denied_paths
  denied_paths="$(echo "${EFFECTIVE}" | jq -r '.allowlist.filesystem.paths.denied[]')"
  while IFS= read -r denied_prefix; do
    [[ -z "${denied_prefix}" ]] && continue
    if [[ "${path}" == "${denied_prefix}"* ]]; then
      report_violation "Path '${path}' matches a denied path prefix: ${denied_prefix}"
      exit 1
    fi
  done <<< "${denied_paths}"
}

check_env_var_allowed() {
  local var="$1"
  if [[ -z "${var}" ]]; then return 0; fi

  local denied
  denied="$(echo "${EFFECTIVE}" | jq -r --arg v "${var}" \
    '.allowlist.environment.denied_vars | index($v) != null')"
  if [[ "${denied}" == "true" ]]; then
    report_violation "Environment variable '${var}' is in the denied_vars list"
    exit 1
  fi
}

check_network_tool() {
  local tool="$1"
  if [[ "${tool}" == "WebFetch" ]] || [[ "${tool}" == "WebSearch" ]]; then
    local outbound
    outbound="$(echo "${EFFECTIVE}" | jq -r '.allowlist.network.outbound')"
    if [[ "${outbound}" != "true" ]]; then
      report_violation "Tool '${tool}' requires network.outbound which is disabled"
      exit 1
    fi
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

log "Checking permission: session=${SESSION_ID} tool=${TOOL} command='${COMMAND}' path='${PATH_ARG}' var='${VAR_ARG}'"

check_tool_allowed    "${TOOL}"
check_command_allowed "${COMMAND}"
check_path_allowed    "${PATH_ARG}"
check_env_var_allowed "${VAR_ARG}"
check_network_tool    "${TOOL}"

log "PERMITTED"
exit 0
