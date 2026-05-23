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
- Python 3 (system `python3` + `uv`, `UV_VERSION=0.10.4`).
- GitHub CLI `GH_VERSION=2.87.2`; oh-my-posh `OMP_VERSION=29.5.0`.
- Go is **not** in the base/tools images. It is installed only in `Dockerfile.code-server` (downloaded from go.dev to `/usr/local/go`). The base/tools Dockerfiles set `GOPATH`/`PATH` env vars but do not install a Go toolchain.
- AI CLIs (tools layer, pinned in `Dockerfile` VERSION TRACKING block): Claude Code, GitHub Copilot, OpenAI Codex, Google Gemini, OpenCode, Backlog.md, Flowspec, GSD, Kiro, MCP Inspector. Versions are pinned in the Dockerfile header — keep them in sync when bumping.

## Image Variants
- `daax-agents-base` (Dockerfile.base) — stable base, rebuild ~monthly.
- `daax-agents` (Dockerfile) — AI CLIs on base, rebuild ~weekly.
- `daax-code-server` (Dockerfile.code-server) — code-server with Go/Node/Python/Rust runtimes; requires `--build-arg TARGETARCH`.
- Specialized: `Dockerfile.core`, `Dockerfile.flowspec`, `Dockerfile.gsd`, `Dockerfile.openspec`.
- `lean/` (Alpine, ~600MB) and `starter-app/` devcontainer variants.

## Build / Package / Registry
- Build: Docker Buildx via `devcontainer/build-push-docker.sh` (2-phase: base then tools) and `build-all.sh`. Local single-image build via `rebuild.sh`.
- Artifact registry: **Docker Hub** (`docker.io/jpoley/daax-agents`, `jpoley/daax-agents-base`). Build cache pushed to `:buildcache` tags. (Image names are kept as `jpoley/*` for now; a daax-dev image-namespace move is a separate decision.)
  - `build-push-docker.sh` also expects a `dhi.io` (Docker Hardened Image) login using the same Docker Hub credentials.
- CI: **none.** No `.github/workflows/` directory exists. Builds/pushes are run manually via `push.sh` / `build-push-docker.sh`.

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
