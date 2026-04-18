#!/bin/bash
# devcontainer/scripts/hot-reload.sh
#
# Issue #7: Claude Code hot-reload support for live agent iteration
#
# Watches CLAUDE.md, .mcp.json, and tool allowlist files for changes.
# On change, reloads the Claude Code agent configuration without restarting
# the container.
#
# Reload strategy (in priority order):
#   1. If claude process is running: send SIGHUP (tells Claude to reload config)
#   2. If CLAUDE_RELOAD_HOOK env var is set: execute that command
#   3. Fall back to: restart any running MCP server process
#
# Watch backend (auto-detected):
#   - inotifywait (inotify-tools) - Linux (preferred)
#   - fswatch                     - macOS / fallback on Linux
#   - poll                        - Portable fallback (checks every 5s)
#
# Usage:
#   hot-reload.sh start      - Start watcher in foreground
#   hot-reload.sh daemon     - Start watcher in background (postStartCommand)
#   hot-reload.sh stop       - Stop background watcher
#   hot-reload.sh status     - Check if watcher is running
#   hot-reload.sh reload     - Trigger a manual reload now
#
# Environment variables:
#   DAAX_WORKSPACE           Workspace root (default: /workspaces/daax)
#   DAAX_STATE_DIR           State directory (default: /tmp/daax-lifecycle)
#   CLAUDE_RELOAD_HOOK       Custom command to run on config change (optional)
#   DAAX_HOT_RELOAD_FILES    Colon-separated list of extra files to watch (optional)
#   DAAX_HOT_RELOAD_POLL_INTERVAL  Poll interval in seconds (default: 5)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
WORKSPACE="${DAAX_WORKSPACE:-/workspaces/daax}"
STATE_DIR="${DAAX_STATE_DIR:-/tmp/daax-lifecycle}"
PID_FILE="${STATE_DIR}/hot-reload.pid"
LOG_FILE="${STATE_DIR}/hot-reload.log"
POLL_INTERVAL="${DAAX_HOT_RELOAD_POLL_INTERVAL:-5}"

# Default files to watch for Claude Code config changes
DEFAULT_WATCH_FILES=(
  "${WORKSPACE}/CLAUDE.md"
  "${WORKSPACE}/.mcp.json"
  "${WORKSPACE}/.claude/settings.json"
  "${WORKSPACE}/.claude/settings.local.json"
  "/home/vscode/.claude/settings.json"
  "/home/vscode/.claude/settings.local.json"
  "/home/vscode/.config/claude/claude_desktop_config.json"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_log() {
  local level="$1"; shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [hot-reload] [$level] $*" | tee -a "${LOG_FILE}" >&2
}

_ensure_state_dir() {
  mkdir -p "${STATE_DIR}"
}

# Build the final list of files/dirs to watch
_watch_targets() {
  local targets=()

  for f in "${DEFAULT_WATCH_FILES[@]}"; do
    # Watch parent directory; inotifywait handles missing files better this way
    local dir
    dir="$(dirname "${f}")"
    if [[ -d "${dir}" ]]; then
      targets+=("${dir}")
    fi
  done

  # Add extra user-configured files
  if [[ -n "${DAAX_HOT_RELOAD_FILES:-}" ]]; then
    IFS=':' read -ra extra <<< "${DAAX_HOT_RELOAD_FILES}"
    for f in "${extra[@]}"; do
      local dir
      dir="$(dirname "${f}")"
      [[ -d "${dir}" ]] && targets+=("${dir}")
    done
  fi

  # Deduplicate
  printf '%s\n' "${targets[@]}" | sort -u
}

# Return true if the changed file is one we care about
_is_watched_file() {
  local changed_file="$1"
  local base
  base="$(basename "${changed_file}")"

  case "${base}" in
    CLAUDE.md|\
    .mcp.json|\
    settings.json|\
    settings.local.json|\
    claude_desktop_config.json|\
    *.allowlist|\
    allowlist.json|\
    allowlist.yaml|\
    allowlist.yml)
      return 0
      ;;
  esac

  # Check user-configured extras
  if [[ -n "${DAAX_HOT_RELOAD_FILES:-}" ]]; then
    IFS=':' read -ra extra <<< "${DAAX_HOT_RELOAD_FILES}"
    for f in "${extra[@]}"; do
      [[ "$(basename "${f}")" == "${base}" ]] && return 0
    done
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Reload logic
# ---------------------------------------------------------------------------

_do_reload() {
  local changed_file="${1:-unknown}"
  _log INFO "Config change detected: ${changed_file}"
  _log INFO "Triggering Claude Code agent reload..."

  # 1. Run custom hook if configured
  if [[ -n "${CLAUDE_RELOAD_HOOK:-}" ]]; then
    _log INFO "Executing CLAUDE_RELOAD_HOOK: ${CLAUDE_RELOAD_HOOK}"
    eval "${CLAUDE_RELOAD_HOOK}" || _log WARN "CLAUDE_RELOAD_HOOK failed (non-fatal)"
    return
  fi

  # 2. Send SIGHUP to any running claude process (asks it to reload config)
  local claude_pids
  claude_pids=$(pgrep -x "claude" 2>/dev/null || pgrep -f "claude-code" 2>/dev/null || true)

  if [[ -n "${claude_pids}" ]]; then
    _log INFO "Sending SIGHUP to claude process(es): ${claude_pids}"
    echo "${claude_pids}" | xargs -r kill -HUP 2>/dev/null || \
      _log WARN "SIGHUP delivery failed (non-fatal; process may have exited)"
    return
  fi

  # 3. Look for and restart MCP server processes
  local mcp_pids
  mcp_pids=$(pgrep -f "mcp" 2>/dev/null || true)

  if [[ -n "${mcp_pids}" ]]; then
    _log INFO "Restarting MCP server process(es): ${mcp_pids}"
    # Gentle restart: SIGTERM then wait; the MCP server's supervisor should restart it
    echo "${mcp_pids}" | xargs -r kill -TERM 2>/dev/null || \
      _log WARN "MCP SIGTERM failed (non-fatal)"
    return
  fi

  _log INFO "No running claude/mcp process found; reload queued for next session start"
  # Write a flag file so the next session start picks up the reload
  touch "${STATE_DIR}/pending-reload"
}

# ---------------------------------------------------------------------------
# Watch backends
# ---------------------------------------------------------------------------

_watch_inotify() {
  local -a targets
  readarray -t targets < <(_watch_targets)

  if [[ ${#targets[@]} -eq 0 ]]; then
    _log WARN "No watchable directories found; falling back to poll"
    _watch_poll
    return
  fi

  _log INFO "Using inotifywait backend (targets: ${targets[*]})"

  inotifywait -m -r \
    -e close_write,moved_to,create,delete \
    --format "%w%f" \
    "${targets[@]}" 2>/dev/null | \
  while IFS= read -r changed; do
    if _is_watched_file "${changed}"; then
      _do_reload "${changed}"
    fi
  done
}

_watch_fswatch() {
  local -a targets
  readarray -t targets < <(_watch_targets)

  if [[ ${#targets[@]} -eq 0 ]]; then
    _log WARN "No watchable directories found; falling back to poll"
    _watch_poll
    return
  fi

  _log INFO "Using fswatch backend (targets: ${targets[*]})"

  fswatch -r "${targets[@]}" | \
  while IFS= read -r changed; do
    if _is_watched_file "${changed}"; then
      _do_reload "${changed}"
    fi
  done
}

_watch_poll() {
  _log INFO "Using poll backend (interval=${POLL_INTERVAL}s)"

  # Build list of actual files that exist
  local all_files=("${DEFAULT_WATCH_FILES[@]}")
  if [[ -n "${DAAX_HOT_RELOAD_FILES:-}" ]]; then
    IFS=':' read -ra extra <<< "${DAAX_HOT_RELOAD_FILES}"
    all_files+=("${extra[@]}")
  fi

  # Capture initial mtimes
  declare -A mtimes
  for f in "${all_files[@]}"; do
    if [[ -f "${f}" ]]; then
      mtimes["${f}"]=$(stat -c "%Y" "${f}" 2>/dev/null || stat -f "%m" "${f}" 2>/dev/null || echo "0")
    fi
  done

  while true; do
    sleep "${POLL_INTERVAL}"
    for f in "${all_files[@]}"; do
      if [[ -f "${f}" ]]; then
        local current_mtime
        current_mtime=$(stat -c "%Y" "${f}" 2>/dev/null || stat -f "%m" "${f}" 2>/dev/null || echo "0")
        local prev_mtime="${mtimes[${f}]:-0}"
        if [[ "${current_mtime}" != "${prev_mtime}" ]]; then
          mtimes["${f}"]="${current_mtime}"
          _do_reload "${f}"
        fi
      fi
    done
  done
}

_start_watcher() {
  if command -v inotifywait >/dev/null 2>&1; then
    _watch_inotify
  elif command -v fswatch >/dev/null 2>&1; then
    _watch_fswatch
  else
    _log WARN "Neither inotifywait nor fswatch found; using poll fallback"
    _log INFO "To suppress this: apt-get install inotify-tools"
    _watch_poll
  fi
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_start() {
  _ensure_state_dir
  _log INFO "Starting hot-reload watcher..."

  # Clear any pending reload flag
  rm -f "${STATE_DIR}/pending-reload"

  _start_watcher
}

cmd_daemon() {
  _ensure_state_dir

  # Guard: only one daemon at a time
  if [[ -f "${PID_FILE}" ]]; then
    local existing_pid
    existing_pid=$(cat "${PID_FILE}")
    if kill -0 "${existing_pid}" 2>/dev/null; then
      _log WARN "Hot-reload daemon already running (pid=${existing_pid})"
      exit 0
    fi
  fi

  _log INFO "Starting hot-reload daemon..."

  # Apply any pending reload from previous session
  if [[ -f "${STATE_DIR}/pending-reload" ]]; then
    _log INFO "Applying pending reload from previous session..."
    rm -f "${STATE_DIR}/pending-reload"
    _do_reload "pending-from-previous-session"
  fi

  # Start watcher in background, record PID
  _start_watcher &
  local watcher_pid=$!
  echo "${watcher_pid}" > "${PID_FILE}"
  _log INFO "Hot-reload daemon started (pid=${watcher_pid})"
}

cmd_stop() {
  if [[ ! -f "${PID_FILE}" ]]; then
    echo "Hot-reload daemon is not running (no PID file)"
    exit 0
  fi

  local pid
  pid=$(cat "${PID_FILE}")
  if kill -0 "${pid}" 2>/dev/null; then
    _log INFO "Stopping hot-reload daemon (pid=${pid})"
    kill "${pid}"
    rm -f "${PID_FILE}"
  else
    _log INFO "PID ${pid} not running; cleaning up stale PID file"
    rm -f "${PID_FILE}"
  fi
}

cmd_status() {
  if [[ ! -f "${PID_FILE}" ]]; then
    echo "Hot-reload daemon: NOT running"
    exit 1
  fi

  local pid
  pid=$(cat "${PID_FILE}")
  if kill -0 "${pid}" 2>/dev/null; then
    echo "Hot-reload daemon: RUNNING (pid=${pid})"
    exit 0
  else
    echo "Hot-reload daemon: STALE PID (pid=${pid}, process not found)"
    exit 1
  fi
}

cmd_reload() {
  _ensure_state_dir
  _log INFO "Manual reload triggered"
  _do_reload "manual"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
  local cmd="${1:-help}"

  case "${cmd}" in
    start)   cmd_start ;;
    daemon)  cmd_daemon ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    reload)  cmd_reload ;;
    help|--help|-h)
      echo "Usage: hot-reload.sh <command>"
      echo ""
      echo "Commands:"
      echo "  start    Start watcher in foreground"
      echo "  daemon   Start watcher in background (used by postStartCommand)"
      echo "  stop     Stop background watcher"
      echo "  status   Show whether the watcher is running"
      echo "  reload   Manually trigger a config reload now"
      echo ""
      echo "Watched files:"
      echo "  CLAUDE.md, .mcp.json, .claude/settings*.json,"
      echo "  claude_desktop_config.json, *.allowlist, allowlist.*"
      echo ""
      echo "Environment:"
      echo "  DAAX_WORKSPACE              Workspace root (default: /workspaces/daax)"
      echo "  DAAX_STATE_DIR              State directory (default: /tmp/daax-lifecycle)"
      echo "  CLAUDE_RELOAD_HOOK          Custom reload command (optional)"
      echo "  DAAX_HOT_RELOAD_FILES       Extra files to watch (colon-separated)"
      echo "  DAAX_HOT_RELOAD_POLL_INTERVAL  Poll interval in seconds (default: 5)"
      echo ""
      echo "Watch backends (auto-detected in order):"
      echo "  1. inotifywait  (apt-get install inotify-tools)"
      echo "  2. fswatch      (brew install fswatch)"
      echo "  3. poll         (portable fallback)"
      ;;
    *)
      echo "Unknown command: ${cmd}" >&2
      echo "Run 'hot-reload.sh help' for usage." >&2
      exit 1
      ;;
  esac
}

main "$@"
