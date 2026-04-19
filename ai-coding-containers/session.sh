#!/usr/bin/env bash
# session.sh — Issue #20
# Provision, start, and stop AI coding containers via docker-agent APIs with
# AI-aware lifecycle hooks.  Each session is linked to hawkeye for monitoring.
#
# Usage:
#   ./session.sh start  --session-id <id> [--image <img>] [--workspace <path>]
#   ./session.sh stop   --session-id <id>
#   ./session.sh status --session-id <id>
#
# Environment variables:
#   DOCKER_AGENT_URL    docker-agent API base URL (default: http://localhost:2376)
#   HAWKEYE_URL         Hawkeye monitoring endpoint (optional)
#   HAWKEYE_TOKEN       Bearer token for hawkeye (optional)
#   SESSION_IMAGE       Default container image (default: jpoley/daax-agents:latest)
#   SESSIONS_DIR        State directory for session metadata (default: /tmp/daax-sessions)
#
# Session lifecycle hooks:
#   on_session_start    — called immediately after container is running
#   on_session_stop     — called before container is removed

set -euo pipefail

# ── defaults ─────────────────────────────────────────────────────────────────

DOCKER_AGENT_URL="${DOCKER_AGENT_URL:-http://localhost:2376}"
HAWKEYE_URL="${HAWKEYE_URL:-}"
HAWKEYE_TOKEN="${HAWKEYE_TOKEN:-}"
SESSION_IMAGE="${SESSION_IMAGE:-jpoley/daax-agents:latest}"
SESSIONS_DIR="${SESSIONS_DIR:-/tmp/daax-sessions}"

# ── helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[session] $*" >&2; }
die()  { echo "[session] ERROR: $*" >&2; exit 1; }
ts()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

usage() {
  cat >&2 <<EOF
Usage:
  $0 start  --session-id <id> [--image <img>] [--workspace <path>]
  $0 stop   --session-id <id>
  $0 status --session-id <id>
EOF
  exit 1
}

# ── hawkeye integration ───────────────────────────────────────────────────────

hawkeye_event() {
  local event="$1"
  local session_id="$2"
  local extra="${3:-{}}"

  if [[ -z "${HAWKEYE_URL}" ]]; then
    log "hawkeye not configured (set HAWKEYE_URL) — skipping event: ${event}"
    return 0
  fi

  local payload
  payload="$(jq -n \
    --arg event      "${event}" \
    --arg session_id "${session_id}" \
    --arg ts         "$(ts)" \
    --argjson extra  "${extra}" \
    '{event: $event, session_id: $session_id, timestamp: $ts} + $extra')"

  log "Posting hawkeye event: ${event} for session ${session_id}"

  local curl_args=(-s -X POST "${HAWKEYE_URL}/api/sessions/events"
    -H "Content-Type: application/json"
    -d "${payload}")

  [[ -n "${HAWKEYE_TOKEN}" ]] && curl_args+=(-H "Authorization: Bearer ${HAWKEYE_TOKEN}")

  local http_code
  http_code="$(curl "${curl_args[@]}" -w '%{http_code}' -o /dev/null 2>&1)" || {
    log "WARNING: hawkeye unreachable — continuing"
    return 0
  }

  if [[ "${http_code}" -ge 200 ]] && [[ "${http_code}" -lt 300 ]]; then
    log "hawkeye event accepted (HTTP ${http_code})"
  else
    log "WARNING: hawkeye returned HTTP ${http_code}"
  fi
}

# ── docker-agent API wrappers ─────────────────────────────────────────────────
#
# docker-agent is the docker engine REST API exposed on DOCKER_AGENT_URL.
# If the URL is the default local socket we fall back to the docker CLI.

docker_api_available() {
  curl -sf "${DOCKER_AGENT_URL}/version" >/dev/null 2>&1
}

# Create and start a container via docker-agent API (REST)
docker_agent_create() {
  local session_id="$1"
  local image="$2"
  local workspace="$3"

  local body
  body="$(jq -n \
    --arg image      "${image}" \
    --arg name       "daax-session-${session_id}" \
    --arg workspace  "${workspace}" \
    '{
      Image: $image,
      Name:  $name,
      Labels: {
        "daax.session_id":  $name,
        "daax.managed":     "true",
        "daax.hawkeye":     "true"
      },
      HostConfig: {
        Binds: [($workspace + ":/workspace:rw")],
        AutoRemove: false
      },
      Env: ["SESSION_ID=" + $name]
    }')"

  curl -sf -X POST "${DOCKER_AGENT_URL}/containers/create?name=daax-session-${session_id}" \
    -H "Content-Type: application/json" \
    -d "${body}" | jq -r '.Id'
}

docker_agent_start() {
  local container_id="$1"
  curl -sf -X POST "${DOCKER_AGENT_URL}/containers/${container_id}/start" >/dev/null
}

docker_agent_stop() {
  local container_id="$1"
  curl -sf -X POST "${DOCKER_AGENT_URL}/containers/${container_id}/stop?t=10" >/dev/null || true
  curl -sf -X DELETE "${DOCKER_AGENT_URL}/containers/${container_id}?force=true" >/dev/null || true
}

docker_agent_inspect() {
  local container_id="$1"
  curl -sf "${DOCKER_AGENT_URL}/containers/${container_id}/json"
}

# Fallback: plain docker CLI
docker_cli_create() {
  local session_id="$1"
  local image="$2"
  local workspace="$3"

  docker create \
    --name "daax-session-${session_id}" \
    -v "${workspace}:/workspace:rw" \
    -e "SESSION_ID=daax-session-${session_id}" \
    -l "daax.session_id=daax-session-${session_id}" \
    -l "daax.managed=true" \
    -l "daax.hawkeye=true" \
    "${image}"
}

docker_cli_start() {
  docker start "$1"
}

docker_cli_stop() {
  docker stop "$1" 2>/dev/null || true
  docker rm -f "$1" 2>/dev/null || true
}

# ── lifecycle hooks ───────────────────────────────────────────────────────────

on_session_start() {
  local session_id="$1"
  local container_id="$2"
  local image="$3"

  log "Hook: on_session_start — session=${session_id} container=${container_id}"

  # Notify hawkeye
  hawkeye_event "session.started" "${session_id}" \
    "$(jq -n --arg cid "${container_id}" --arg img "${image}" \
      '{container_id: $cid, image: $img}')"

  # Placeholder: run any user-defined start hook scripts from session dir
  local hook_script="${SESSIONS_DIR}/${session_id}/hooks/on_start.sh"
  if [[ -x "${hook_script}" ]]; then
    log "Running custom on_start hook: ${hook_script}"
    "${hook_script}" "${session_id}" "${container_id}" || \
      log "WARNING: on_start hook exited with non-zero status"
  fi
}

on_session_stop() {
  local session_id="$1"
  local container_id="$2"

  log "Hook: on_session_stop — session=${session_id} container=${container_id}"

  # Notify hawkeye
  hawkeye_event "session.stopped" "${session_id}" \
    "$(jq -n --arg cid "${container_id}" '{container_id: $cid}')"

  # Placeholder: run custom stop hook
  local hook_script="${SESSIONS_DIR}/${session_id}/hooks/on_stop.sh"
  if [[ -x "${hook_script}" ]]; then
    log "Running custom on_stop hook: ${hook_script}"
    "${hook_script}" "${session_id}" "${container_id}" || \
      log "WARNING: on_stop hook exited with non-zero status"
  fi
}

# ── session state ─────────────────────────────────────────────────────────────

save_session() {
  local session_id="$1"
  local container_id="$2"
  local image="$3"
  local workspace="$4"

  mkdir -p "${SESSIONS_DIR}/${session_id}"
  jq -n \
    --arg session_id   "${session_id}" \
    --arg container_id "${container_id}" \
    --arg image        "${image}" \
    --arg workspace    "${workspace}" \
    --arg started_at   "$(ts)" \
    '{session_id: $session_id, container_id: $container_id,
      image: $image, workspace: $workspace, started_at: $started_at}' \
    > "${SESSIONS_DIR}/${session_id}/session.json"
}

load_session() {
  local session_id="$1"
  local state_file="${SESSIONS_DIR}/${session_id}/session.json"
  [[ -f "${state_file}" ]] || die "Session not found: ${session_id}"
  cat "${state_file}"
}

# ── subcommands ───────────────────────────────────────────────────────────────

cmd_start() {
  local session_id=""
  local image="${SESSION_IMAGE}"
  local workspace="${PWD}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      --image)      image="$2";      shift 2 ;;
      --workspace)  workspace="$2";  shift 2 ;;
      *) die "Unknown flag: $1" ;;
    esac
  done

  [[ -z "${session_id}" ]] && die "--session-id is required"

  log "Provisioning AI coding session: ${session_id}"
  log "  Image:     ${image}"
  log "  Workspace: ${workspace}"

  local container_id

  if docker_api_available; then
    log "Using docker-agent API at ${DOCKER_AGENT_URL}"
    container_id="$(docker_agent_create "${session_id}" "${image}" "${workspace}")"
    docker_agent_start "${container_id}"
  else
    log "docker-agent API not available — using docker CLI"
    container_id="$(docker_cli_create "${session_id}" "${image}" "${workspace}")"
    docker_cli_start "${container_id}"
  fi

  log "Container started: ${container_id}"
  save_session "${session_id}" "${container_id}" "${image}" "${workspace}"
  on_session_start "${session_id}" "${container_id}" "${image}"

  echo ""
  echo "Session started:"
  echo "  session_id:   ${session_id}"
  echo "  container_id: ${container_id}"
  echo "  image:        ${image}"
  echo "  workspace:    ${workspace}"
  echo ""
  echo "To stop: $0 stop --session-id ${session_id}"
}

cmd_stop() {
  local session_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      *) die "Unknown flag: $1" ;;
    esac
  done

  [[ -z "${session_id}" ]] && die "--session-id is required"

  local state
  state="$(load_session "${session_id}")"
  local container_id
  container_id="$(echo "${state}" | jq -r '.container_id')"

  log "Stopping session: ${session_id} (container: ${container_id})"
  on_session_stop "${session_id}" "${container_id}"

  if docker_api_available; then
    docker_agent_stop "${container_id}"
  else
    docker_cli_stop "${container_id}"
  fi

  rm -rf "${SESSIONS_DIR}/${session_id}"
  log "Session ${session_id} stopped and removed."
}

cmd_status() {
  local session_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      *) die "Unknown flag: $1" ;;
    esac
  done

  [[ -z "${session_id}" ]] && die "--session-id is required"

  local state
  state="$(load_session "${session_id}")"
  local container_id
  container_id="$(echo "${state}" | jq -r '.container_id')"

  local inspect
  if docker_api_available; then
    inspect="$(docker_agent_inspect "${container_id}" 2>/dev/null || echo '{}')"
  else
    inspect="$(docker inspect "${container_id}" 2>/dev/null | jq '.[0] // {}' || echo '{}')"
  fi

  local status
  status="$(echo "${inspect}" | jq -r '.State.Status // "unknown"')"

  echo "${state}" | jq --arg container_status "${status}" '. + {container_status: $container_status}'
}

# ── main ─────────────────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage

SUBCOMMAND="$1"; shift

case "${SUBCOMMAND}" in
  start)  cmd_start  "$@" ;;
  stop)   cmd_stop   "$@" ;;
  status) cmd_status "$@" ;;
  *)      die "Unknown subcommand: ${SUBCOMMAND}. Use start | stop | status" ;;
esac
