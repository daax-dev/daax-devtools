# Stack

`[FILL IN]` marks an undefined entry. Treat as "ask the operator," not a guess.
Only document what is confirmed and deployable today.

This is an infrastructure / container-tooling repo. The repo's own source is shell scripts, Dockerfiles, and JSON config — there is no application runtime at the repo root. The runtimes below ship *inside the images this repo builds*.

---

## Repo Tooling (what runs at the repo root)
- POSIX/Bash shell scripts (`*.sh`).
- Docker / Docker Buildx (multi-arch builds: `linux/amd64,linux/arm64`).
- `package.json` scripts invoked with **`bun`** (`bun run agents:build|push|release`).

## Image Runtimes (inside the built images)
- Base image: `node:22-bookworm-slim` (Debian bookworm-slim).
- Node.js 22 + pnpm.
- Python 3 (system `python3` + `uv`, `UV_VERSION=0.11.7`).
- Go (binaries copied from a builder stage — no `go.mod` in this repo).
- GitHub CLI `GH_VERSION=2.90.0`; oh-my-posh `OMP_VERSION=29.10.0`.
- AI CLIs (tools layer, pinned in `Dockerfile` VERSION TRACKING block): Claude Code, GitHub Copilot, OpenAI Codex, Google Gemini, OpenCode, Backlog.md, Flowspec, GSD, Kiro, MCP Inspector. Versions are pinned in the Dockerfile header — keep them in sync when bumping.

## Image Variants
- `daax-agents-base` (Dockerfile.base) — stable base, rebuild ~monthly.
- `daax-agents` (Dockerfile) — AI CLIs on base, rebuild ~weekly.
- `daax-code-server` (Dockerfile.code-server) — code-server with Go/Node/Python/Rust runtimes; requires `--build-arg TARGETARCH`.
- Specialized: `Dockerfile.core`, `Dockerfile.flowspec`, `Dockerfile.gsd`, `Dockerfile.openspec`.
- `lean/` (Alpine, ~600MB) and `starter-app/` devcontainer variants.

## Build / Package / Registry
- Build: Docker Buildx via `devcontainer/build-push-docker.sh` (2-phase: base then tools) and `build-all.sh`. Local single-image build via `rebuild.sh`.
- Artifact registry: **Docker Hub** (`docker.io/jpoley/daax-agents`, `jpoley/daax-agents-base`). Build cache pushed to `:buildcache` tags.
  - Known discrepancy: `README.md` calls it "GitHub Container Registry," but all scripts target Docker Hub. The scripts are authoritative. Out of scope to fix here.
  - `build-push-docker.sh` also expects a `dhi.io` (Docker Hardened Image) login using the same Docker Hub credentials.
- CI: **none.** `Dockerfile.base` header references `.github/workflows/docker-publish.yml` as a future/aspirational automation target, but no workflow file exists in the repo. Builds/pushes are run manually.

## Persistence / Messaging / Auth
- None applicable — this repo ships no service.
- Auth used by tooling: Docker Hub login (`docker login`), and `GITHUB_DAAX` token for pulling/pushing during builds. Both come from the environment — never committed.

## Deployment Targets / Integration
- Consumed by daax-cli and daax-web for AI coding sessions.
- `restart.sh` runs the `daax` container locally on ports 4200/4201, mounting `DAAX_WORKSPACE` (default `~/prj`) and the Docker socket.
- Tailscale used as a network deployment target (per repo docs).

## Explicitly Not in Stack
- No `docker-compose.yml` in this repo — compose orchestration lives in the daax-web project.
- No application source, no test framework, no lockfile at the repo root.
