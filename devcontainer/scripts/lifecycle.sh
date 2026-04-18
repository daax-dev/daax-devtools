#!/bin/bash
# devcontainer/scripts/lifecycle.sh
#
# Issue #5: docker/docker-agent runtime for AI-aware container lifecycle
#
# Manages the container session lifecycle:
#   - Records session open/close timestamps
#   - Detects idle state via last-activity file
#   - Emits lifecycle events to Hawkeye SSE endpoint (if HAWKEYE_URL is set)
#   - Optionally pauses container on idle; snapshots state before teardown
#
# Usage:
#   lifecycle.sh open          - Called on session start (postStartCommand)
#   lifecycle.sh close         - Called on container stop / pre-teardown
#   lifecycle.sh idle-check    - Check idle state; exits 0 if idle, 1 if active
#   lifecycle.sh touch          - Update last-activity timestamp (call from shell init)
#   lifecycle.sh daemon        - Run idle watchdog in background
#
# Environment variables:
#   HAWKEYE_URL           - Base URL of Hawkeye event endpoint (optional)
#                           e.g. https://hawkeye.example.com
#   DAAX_IDLE_TIMEOUT     - Seconds of inactivity before "idle" (default: 300)
#   DAAX_STATE_DIR        - Directory for lifecycle state files
#                           (default: /tmp/daax-lifecycle)
#   DAAX_CONTAINER_ID     - Override container ID for event metadata
#   DAAX_WORKSPACE        - Workspace path (default: /workspaces/daax)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
IDLE_TIMEOUT="${DAAX_IDLE_TIMEOUT:-300}"          # seconds; default 5 min
STATE_DIR="${DAAX_STATE_DIR:-/tmp/daax-lifecycle}"
WORKSPACE="${DAAX_WORKSPACE:-/workspaces/daax}"
ACTIVITY_FILE="${STATE_DIR}/last-activity"
PID_FILE="${STATE_DIR}/idle-daemon.pid"
LOG_FILE="${STATE_DIR}/lifecycle.log"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_log() {
  local level="$1"; shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [lifecycle] [$level] $*" | tee -a "${LOG_FILE}" >&2
}

_container_id() {
  # Prefer explicit override, then try Docker-style cgroup, then hostname
  if [[ -n "${DAAX_CONTAINER_ID:-}" ]]; then
    echo "${DAAX_CONTAINER_ID}"
    return
  fi
  if [[ -f /proc/self/cgroup ]]; then
    grep -oE '[0-9a-f]{64}' /proc/self/cgroup 2>/dev/null | head -1 || hostname
  else
    hostname
  fi
}

_ensure_state_dir() {
  mkdir -p "${STATE_DIR}"
}

# ---------------------------------------------------------------------------
# Hawkeye event emission
# ---------------------------------------------------------------------------

_emit_event() {
  local event_type="$1"  # session_open | session_close | session_idle | session_active
  local extra="${2:-}"

  if [[ -z "${HAWKEYE_URL:-}" ]]; then
    _log DEBUG "HAWKEYE_URL not set; skipping event emission (event=${event_type})"
    return 0
  fi

  local container_id
  container_id="$(_container_id)"

  local payload
  payload=$(cat <<EOF
{
  "source": "daax-devcontainer",
  "container_id": "${container_id}",
  "workspace": "${WORKSPACE}",
  "event": "${event_type}",
  "timestamp": "$(_ts)",
  "metadata": {
    "idle_timeout": ${IDLE_TIMEOUT},
    "extra": "${extra}"
  }
}
EOF
)

  _log INFO "Emitting event '${event_type}' to ${HAWKEYE_URL}/events"

  if ! curl -sf \
    --max-time 5 \
    -X POST \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${HAWKEYE_URL}/events" >/dev/null 2>&1; then
    # Non-fatal: Hawkeye may be unavailable; log and continue
    _log WARN "Failed to emit event '${event_type}' to Hawkeye (non-fatal)"
  fi
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_open() {
  _ensure_state_dir
  _log INFO "Session opened"
  cmd_touch  # seed the last-activity timestamp
  echo "$(_ts)" > "${STATE_DIR}/session-start"
  _emit_event "session_open"
}

cmd_close() {
  _ensure_state_dir
  _log INFO "Session closing"

  # Request a snapshot before teardown if snapshot.sh is available
  local snapshot_script
  snapshot_script="$(dirname "$0")/snapshot.sh"
  if [[ -x "${snapshot_script}" ]]; then
    _log INFO "Requesting pre-teardown snapshot..."
    "${snapshot_script}" snapshot "pre-teardown" 2>&1 | tee -a "${LOG_FILE}" || \
      _log WARN "Snapshot failed (non-fatal)"
  fi

  _emit_event "session_close"

  # Stop the idle daemon if running
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid=$(cat "${PID_FILE}")
    if kill -0 "${pid}" 2>/dev/null; then
      _log INFO "Stopping idle daemon (pid=${pid})"
      kill "${pid}" 2>/dev/null || true
    fi
    rm -f "${PID_FILE}"
  fi
}

cmd_touch() {
  _ensure_state_dir
  date +%s > "${ACTIVITY_FILE}"
}

cmd_idle_check() {
  if [[ ! -f "${ACTIVITY_FILE}" ]]; then
    _log DEBUG "No activity file; treating as idle"
    exit 0  # idle
  fi

  local last_activity now elapsed
  last_activity=$(cat "${ACTIVITY_FILE}")
  now=$(date +%s)
  elapsed=$(( now - last_activity ))

  if (( elapsed >= IDLE_TIMEOUT )); then
    _log INFO "Idle detected: ${elapsed}s since last activity (threshold=${IDLE_TIMEOUT}s)"
    exit 0  # idle
  else
    _log DEBUG "Active: ${elapsed}s since last activity (threshold=${IDLE_TIMEOUT}s)"
    exit 1  # active
  fi
}

cmd_daemon() {
  _ensure_state_dir

  # Guard: only one daemon at a time
  if [[ -f "${PID_FILE}" ]]; then
    local existing_pid
    existing_pid=$(cat "${PID_FILE}")
    if kill -0 "${existing_pid}" 2>/dev/null; then
      _log WARN "Idle daemon already running (pid=${existing_pid}); exiting"
      exit 0
    fi
  fi

  echo $$ > "${PID_FILE}"
  _log INFO "Idle daemon started (pid=$$, idle_timeout=${IDLE_TIMEOUT}s)"

  local was_idle=false

  while true; do
    sleep 30  # poll every 30 seconds

    if cmd_idle_check 2>/dev/null; then
      # System is idle
      if [[ "${was_idle}" == false ]]; then
        _log INFO "Container entered idle state"
        _emit_event "session_idle" "elapsed_seconds=$(( $(date +%s) - $(cat "${ACTIVITY_FILE}" 2>/dev/null || echo "$(date +%s)") ))"
        was_idle=true
      fi
    else
      # System is active
      if [[ "${was_idle}" == true ]]; then
        _log INFO "Container returned to active state"
        _emit_event "session_active"
        was_idle=false
      fi
    fi
  done
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
  local cmd="${1:-help}"

  case "${cmd}" in
    open)        cmd_open ;;
    close)       cmd_close ;;
    touch)       cmd_touch ;;
    idle-check)  cmd_idle_check ;;
    daemon)      cmd_daemon ;;
    help|--help|-h)
      echo "Usage: lifecycle.sh <command>"
      echo ""
      echo "Commands:"
      echo "  open         Record session start; emit session_open event"
      echo "  close        Snapshot workspace; emit session_close event; stop daemon"
      echo "  touch        Update last-activity timestamp (call from shell init)"
      echo "  idle-check   Exit 0 if idle, 1 if active"
      echo "  daemon       Run idle watchdog in background (started by postStartCommand)"
      echo ""
      echo "Environment:"
      echo "  HAWKEYE_URL         Hawkeye SSE base URL (optional)"
      echo "  DAAX_IDLE_TIMEOUT   Idle threshold in seconds (default: 300)"
      echo "  DAAX_STATE_DIR      State directory (default: /tmp/daax-lifecycle)"
      ;;
    *)
      echo "Unknown command: ${cmd}" >&2
      echo "Run 'lifecycle.sh help' for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
