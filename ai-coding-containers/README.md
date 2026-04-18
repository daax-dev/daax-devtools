# ai-coding-containers

Scripts and configuration for provisioning sandboxed AI coding sessions with enforced tool permissions and reproducible environment bootstrapping.

## Files

### `session.sh` — Issue #20: AI coding container lifecycle

Provisions, starts, and stops AI coding containers via docker-agent APIs with AI-aware lifecycle hooks. Each session is linked to hawkeye for monitoring.

```bash
# Start a session
./session.sh start --session-id my-session --workspace /path/to/project

# Check status
./session.sh status --session-id my-session

# Stop and remove the session
./session.sh stop --session-id my-session
```

**Lifecycle hooks:**

| Hook | When | What it does |
|---|---|---|
| `on_session_start` | After container starts | Notifies hawkeye, runs `hooks/on_start.sh` if present |
| `on_session_stop` | Before container stops | Notifies hawkeye, runs `hooks/on_stop.sh` if present |

Custom hooks can be placed at `<SESSIONS_DIR>/<session-id>/hooks/on_start.sh` and `on_stop.sh`.

**Environment variables:**

| Variable | Default | Purpose |
|---|---|---|
| `DOCKER_AGENT_URL` | `http://localhost:2376` | docker-agent API URL (falls back to docker CLI) |
| `HAWKEYE_URL` | — | Monitoring endpoint |
| `HAWKEYE_TOKEN` | — | Bearer token for hawkeye |
| `SESSION_IMAGE` | `jpoley/daax-agents:latest` | Default container image |
| `SESSIONS_DIR` | `/tmp/daax-sessions` | Session state directory |

---

### `permissions.json` — Issue #21: Default tool allowlist

Defines the default tool allowlist for sandboxed AI coding sessions. Session creators can only narrow this list, never expand it. hawkeye enforces the allowlist at runtime.

Key defaults:

- **Filesystem**: read + write within `/workspace`; no writes to `/etc`, `/var`, system paths
- **Network**: outbound and inbound disabled by default
- **Processes**: curated allowlist of safe commands; `sudo`, `docker`, `ssh`, `wget`, etc. are denied
- **Environment**: sensitive tokens (`GITHUB_TOKEN`, `*_API_KEY`, etc.) blocked from env access
- **Tools**: `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep` permitted; `WebFetch`, `WebSearch` denied

---

### `enforce-permissions.sh` — Issue #21: Runtime permission enforcement

Validates a proposed tool call against the effective session allowlist (default narrowed by any session-level override). Reports violations to hawkeye.

```bash
# Check if a tool call is permitted
./enforce-permissions.sh --session-id my-session --tool Bash --command "git status"

# Check a file path
./enforce-permissions.sh --session-id my-session --tool Read --path /workspace/src/app.py

# Check an env var access
./enforce-permissions.sh --session-id my-session --tool Bash --var GITHUB_TOKEN
```

Exit codes: `0` = permitted, `1` = denied (violation logged to hawkeye), `2` = usage error.

**Session-level permission overrides:**

To narrow the default allowlist for a specific session, place a `permissions.json` in the session directory:

```
/tmp/daax-sessions/<session-id>/permissions.json
```

The effective permissions are the intersection (most restrictive) of the default and session-level configs. A session can only remove tools from the allowlist, add to the denied list — never re-enable a tool that the default denies.

**Environment variables:**

| Variable | Default | Purpose |
|---|---|---|
| `DEFAULT_PERMISSIONS` | `./permissions.json` | Base allowlist |
| `SESSIONS_DIR` | `/tmp/daax-sessions` | Session state directory |
| `HAWKEYE_URL` | — | Violation reporting endpoint |
| `HAWKEYE_TOKEN` | — | Bearer token for hawkeye |

---

### `tool-lockfile.json` — Issue #22: Pinned tool versions

Declarative lockfile specifying exact versions and SHA-256/integrity checksums for every tool installed in the AI coding container. `bootstrap.sh` reads this file and fails the build if any version or checksum drifts.

Update the lockfile when upgrading tools:

```bash
# Get npm integrity hash
npm view @anthropic-ai/claude-code@1.9.3 dist.integrity

# Get Docker image digest
docker inspect jpoley/daax-agents:latest | jq -r '.[0].RepoDigests[0]'
```

---

### `bootstrap.sh` — Issue #22: Reproducible environment bootstrap

Reads `tool-lockfile.json`, installs (unless `--verify-only`), and verifies every tool version and checksum. Fails immediately on any drift. Computes a build hash to verify two identical builds produce the same environment.

```bash
# Install and verify all tools
./bootstrap.sh

# Verify only (no installs)
./bootstrap.sh --verify-only

# Use a custom lockfile
./bootstrap.sh --lockfile /path/to/tool-lockfile.json
```

**What it checks:**

1. npm package versions match lockfile (and integrity hash if not a placeholder)
2. Python package versions match lockfile
3. System binary minimum versions (`docker`, `jq`, `git`)
4. Build hash matches the previous bootstrap run (reproducibility proof)

**Environment variables:**

| Variable | Default | Purpose |
|---|---|---|
| `LOCKFILE` | `./tool-lockfile.json` | Path to lockfile |
| `VERIFY_ONLY` | `false` | Skip installs, only verify |
| `BUILD_HASH_FILE` | `../testcontainers/results/bootstrap.hash` | Hash file for reproducibility check |
| `PNPM_HOME` | `~/.local/share/pnpm` | pnpm global bin directory |

---

## Typical workflow

```bash
# 1. Bootstrap the environment (install + verify all pinned tools)
./bootstrap.sh

# 2. Start a session
./session.sh start --session-id dev-$(date +%s) --workspace ~/myproject

# 3. Tool calls go through the permission enforcement layer
./enforce-permissions.sh --session-id dev-1234 --tool Bash --command "pytest tests/"

# 4. Stop the session when done
./session.sh stop --session-id dev-1234
```
