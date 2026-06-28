#!/usr/bin/env bash
#
# Integration harness for `daax dev generate-tests`.
#
# Proves the issue's Definition of Done against REAL toolchains (not just
# syntax): the generated Go compiles against testcontainers-go, the generated
# TypeScript typechecks against the testcontainers npm packages, and — when a
# Docker daemon is reachable — the generated code actually starts the declared
# containers and returns connection strings.
#
# Usage:  scripts/verify-generated.sh
# Env:    SKIP_DOCKER=1   compile/typecheck only, skip live container starts.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GEN() { bun run src/generate-tests/cli.ts "$@"; }

have_docker() {
  [[ "${SKIP_DOCKER:-0}" == "1" ]] && return 1
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

echo "==> [1/4] Go compiles against testcontainers-go (multi fixture)"
GEN --devcontainer tests/fixtures/multi/devcontainer.json --lang go --out "$WORK/go" >/dev/null
(
  cd "$WORK/go"
  go mod init tcgen-verify >/dev/null 2>&1
  go mod tidy >/dev/null 2>&1
  go vet ./...
)
echo "    OK: go vet passed"

echo "==> [2/4] TypeScript typechecks against the testcontainers packages (multi fixture)"
GEN --devcontainer tests/fixtures/multi/devcontainer.json --lang ts --out "$WORK/ts" >/dev/null
cat > "$WORK/ts/tsconfig.json" <<EOF
{
  "extends": "$REPO_ROOT/tsconfig.json",
  "compilerOptions": {
    "noEmit": true,
    "typeRoots": ["$REPO_ROOT/node_modules/@types"],
    "baseUrl": "$REPO_ROOT",
    "paths": { "*": ["node_modules/*"] }
  },
  "include": ["*.ts"]
}
EOF
"$REPO_ROOT/node_modules/.bin/tsc" -p "$WORK/ts/tsconfig.json"
echo "    OK: tsc passed"

if ! have_docker; then
  echo "==> [3/4] SKIP live Go container start (no Docker)"
  echo "==> [4/4] SKIP live TS container start (no Docker)"
  echo "All compile/typecheck checks passed."
  exit 0
fi

echo "==> [3/4] Go starts a live postgres:15 container (postgres fixture)"
GEN --devcontainer tests/fixtures/postgres/devcontainer.json --lang go --out "$WORK/golive" >/dev/null
(
  cd "$WORK/golive"
  go mod init tcgen-live >/dev/null 2>&1
  go mod tidy >/dev/null 2>&1
  go test -run TestDbConnection ./...
)
echo "    OK: postgres container started and returned a connection string"

echo "==> [4/4] TS starts a live redis:7 container (redis fixture)"
mkdir -p "$WORK/redisfix"
cat > "$WORK/redisfix/docker-compose.yml" <<'EOF'
services:
  app:
    build: .
  cache:
    image: redis:7
    ports: ["6379:6379"]
EOF
cat > "$WORK/redisfix/devcontainer.json" <<'EOF'
{ "service": "app", "dockerComposeFile": "docker-compose.yml" }
EOF
# vitest only collects files under its root, so emit into an in-repo scratch dir.
LIVE_DIR="$REPO_ROOT/.tc-live-int"
rm -rf "$LIVE_DIR"; mkdir -p "$LIVE_DIR"
trap 'rm -rf "$WORK" "$LIVE_DIR"' EXIT
GEN --devcontainer "$WORK/redisfix/devcontainer.json" --lang ts --out "$LIVE_DIR" >/dev/null
"$REPO_ROOT/node_modules/.bin/vitest" run --root "$REPO_ROOT" "$LIVE_DIR/testcontainers.test.ts"
echo "    OK: redis container started under vitest"

echo "All checks passed (compile + typecheck + live container starts)."
