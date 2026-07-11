#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"
EXPECTED_VERSION="${HERDR_EXPECTED_VERSION:-${HERDR_VERSION:-0.7.1}}"
EXPECTED_VERSION="${EXPECTED_VERSION#v}"

log() {
  printf '[herdr:%s] %s\n' "$MODE" "$*"
}

fail() {
  printf '[herdr:%s] ERROR: %s\n' "$MODE" "$*" >&2
  exit 1
}

VERIFY_TMP="$(mktemp -d "${TMPDIR:-/tmp}/herdr-verify.XXXXXX")" \
  || fail "could not create verification temp directory"

cleanup_verify_tmp() {
  local status=$?
  if [[ "${KEEP_HERDR_VERIFY_LOGS:-}" == "1" || "${KEEP_HERDR_SMOKE_LOGS:-}" == "1" ]]; then
    log "kept verification logs in $VERIFY_TMP"
  else
    rm -rf "$VERIFY_TMP"
  fi
  return "$status"
}

trap cleanup_verify_tmp EXIT

RUNTIME_SMOKE_TMP=""
RUNTIME_SMOKE_SERVER_PID=""
RUNTIME_SMOKE_CLEANED=0

cleanup_runtime_smoke() {
  if [[ "$RUNTIME_SMOKE_CLEANED" == "1" ]]; then
    return 0
  fi
  RUNTIME_SMOKE_CLEANED=1

  if [[ -n "$RUNTIME_SMOKE_SERVER_PID" ]]; then
    herdr server stop >/dev/null 2>&1 || true

    local i
    for i in $(seq 1 20); do
      if ! kill -0 "$RUNTIME_SMOKE_SERVER_PID" >/dev/null 2>&1; then
        wait "$RUNTIME_SMOKE_SERVER_PID" >/dev/null 2>&1 || true
        break
      fi
      sleep 0.1
    done

    if kill -0 "$RUNTIME_SMOKE_SERVER_PID" >/dev/null 2>&1; then
      kill "$RUNTIME_SMOKE_SERVER_PID" >/dev/null 2>&1 || true
      for i in $(seq 1 10); do
        if ! kill -0 "$RUNTIME_SMOKE_SERVER_PID" >/dev/null 2>&1; then
          break
        fi
        sleep 0.1
      done
    fi

    if kill -0 "$RUNTIME_SMOKE_SERVER_PID" >/dev/null 2>&1; then
      kill -KILL "$RUNTIME_SMOKE_SERVER_PID" >/dev/null 2>&1 || true
    fi
    wait "$RUNTIME_SMOKE_SERVER_PID" >/dev/null 2>&1 || true
    RUNTIME_SMOKE_SERVER_PID=""
  fi

  if [[ -n "$RUNTIME_SMOKE_TMP" && "${KEEP_HERDR_SMOKE_LOGS:-}" == "1" ]]; then
    log "kept smoke logs in $RUNTIME_SMOKE_TMP"
  fi
}

cleanup_runtime_and_tmp() {
  local status=$?
  cleanup_runtime_smoke
  cleanup_verify_tmp
  return "$status"
}

require_herdr() {
  command -v herdr >/dev/null 2>&1 || fail "herdr is not on PATH"

  local version help
  version="$(herdr --version 2>&1)"
  log "$version"
  case "$version" in
    *"$EXPECTED_VERSION"*) ;;
    *) fail "expected Herdr version $EXPECTED_VERSION, got: $version" ;;
  esac

  help="$(herdr --help 2>&1 || true)"
  grep -q 'integration <subcommand>' <<<"$help" \
    || fail "herdr --help does not list integration support"

  help="$(herdr workspace --help 2>&1 || true)"
  grep -q 'workspace create' <<<"$help" \
    || fail "herdr workspace CLI is not available"

  help="$(herdr agent --help 2>&1 || true)"
  grep -q 'agent start' <<<"$help" \
    || fail "herdr agent start CLI is not available"

  help="$(herdr pane --help 2>&1 || true)"
  grep -q 'pane read' <<<"$help" \
    || fail "herdr pane read CLI is not available"

  help="$(herdr session --help 2>&1 || true)"
  grep -q 'session list' <<<"$help" \
    || fail "herdr session CLI is not available"
  herdr status --json >"$VERIFY_TMP/herdr-status.json"
  herdr integration status >"$VERIFY_TMP/herdr-integration-status.txt"
}

wait_for_server() {
  local tmp="$1"
  local i
  for i in $(seq 1 100); do
    if herdr status server --json 2>"$tmp/herdr-status-server.err" \
      | tee "$tmp/herdr-status-server.json" \
      | grep -q '"running":true'; then
      return 0
    fi
    sleep 0.1
  done
  cat "$tmp/herdr-status-server.err" >&2 2>/dev/null || true
  cat "$tmp/herdr-status-server.json" >&2 2>/dev/null || true
  return 1
}

read_agent_until() {
  local agent="$1"
  local token="$2"
  local out_file="$3"
  local i

  for ((i = 1; i <= 50; i++)); do
    herdr agent read "$agent" --source recent --lines 50 >"$out_file" || true
    if grep -q "$token" "$out_file"; then
      return 0
    fi
    sleep 0.2
  done

  cat "$out_file" >&2 2>/dev/null || true
  return 1
}

runtime_smoke() {
  local tmp server_pid
  tmp="$VERIFY_TMP/smoke"
  RUNTIME_SMOKE_TMP="$tmp"
  export HOME="$tmp/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$tmp" "$HOME" "$XDG_CONFIG_HOME"

  herdr server >"$tmp/server.log" 2>&1 &
  server_pid="$!"
  RUNTIME_SMOKE_SERVER_PID="$server_pid"

  trap cleanup_runtime_and_tmp EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  wait_for_server "$tmp" || {
    sed -n '1,160p' "$tmp/server.log" >&2 || true
    fail "Herdr server did not become ready"
  }

  herdr session list --json >"$tmp/herdr-session-list.json"
  herdr workspace list >"$tmp/herdr-workspace-list.txt"
  herdr workspace create --cwd "$tmp" --label daax-herdr-smoke --no-focus \
    >"$tmp/herdr-workspace-create.txt"

  # shellcheck disable=SC2016
  herdr agent start codex-smoke --cwd "$tmp" --no-focus -- \
    /bin/sh -lc 'i=0; while [ "$i" -lt 40 ]; do echo C_OK; i=$((i + 1)); sleep 0.25; done; sleep 20' \
    >"$tmp/herdr-agent-start-codex.txt"
  # shellcheck disable=SC2016
  herdr agent start claude-smoke --cwd "$tmp" --split right --no-focus -- \
    /bin/sh -lc 'i=0; while [ "$i" -lt 40 ]; do echo D_OK; i=$((i + 1)); sleep 0.25; done; sleep 20' \
    >"$tmp/herdr-agent-start-claude.txt"

  sleep 0.2
  herdr agent list >"$tmp/herdr-agent-list.txt"
  herdr pane list >"$tmp/herdr-pane-list.txt"

  read_agent_until codex-smoke C_OK "$tmp/herdr-agent-read-codex.txt" \
    || fail "codex-smoke output was not readable through Herdr"
  read_agent_until claude-smoke D_OK "$tmp/herdr-agent-read-claude.txt" \
    || fail "claude-smoke output was not readable through Herdr"

  herdr server stop >"$tmp/herdr-server-stop.txt"
  wait "$server_pid" >/dev/null 2>&1 || true
  RUNTIME_SMOKE_SERVER_PID=""
  trap cleanup_verify_tmp EXIT
  trap - INT TERM
}

require_herdr

case "$MODE" in
  build|basic)
    log "basic verification passed"
    ;;
  runtime|smoke|e2e)
    runtime_smoke
    log "runtime smoke passed"
    ;;
  *)
    fail "unknown mode: $MODE"
    ;;
esac
