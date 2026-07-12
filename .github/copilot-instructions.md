# Copilot Instructions

GitHub Copilot reads this file automatically and loads it as instructions for each session.

---

## Project
Name: daax-devtools
Purpose: Container/devcontainer tooling for the Daax platform — Dockerfiles, devcontainer configs, and shell scripts that build and publish the `daax-agents` AI-coding images to Docker Hub.

---

## Operator Preferences
<!-- Operator-specific. Revise or replace when applying to a different operator. -->
- State facts only. No sugarcoating.
- Surface problems, blockers, and risks immediately.
- Consult before one-way-door or architectural decisions.
- Never answer from a guess. Say so when a claim cannot be validated.
- Objective language. No first-person pronouns. No apologies.

---

## Planning
- A plan is required for any non-trivial change. Trivial = typo fix, single-line config update, obvious rename.
- Write the plan first. Present it. Wait for approval. Do not start coding until approved.
- Present options with trade-offs. The operator decides; the agent executes.

---

## Stack
- This is an infrastructure/tooling repo. The repo's own source is **shell scripts + Dockerfiles + JSON config** — no application code, no application build/runtime at the repo root (root scripts like `./push.sh`, `./rebuild.sh`, and `bun run agents:*` drive image builds, not an app build).
- Container images built here run: Python 3 (Debian bookworm-slim), Node.js 22. Those runtimes live *inside the images*, not in this repo. Go is **not** in the base/tools images — it ships only in `Dockerfile.code-server` (downloaded from go.dev to `/usr/local/go`). The tools `Dockerfile` sets `GOPATH` and extends `PATH`; `Dockerfile.base` sets `PATH` only (no `GOPATH`).
- Image base: `node:22-bookworm-slim`. Pinned build args (`Dockerfile.base`): `GH_VERSION=2.87.2`, `UV_VERSION=0.10.4`, `OMP_VERSION=29.5.0`. Trust the Dockerfiles when these drift.
- Package manager: `package.json` scripts are invoked with `bun` (`bun run agents:release`). uv + pnpm are installed inside images, not used at repo root.
- Registry: **Docker Hub** (`docker.io/jpoley/daax-agents`, `jpoley/daax-agents-base`). The scripts (`push.sh`, `build-push-docker.sh`, `package.json`) all target Docker Hub.
- CI: none. No `.github/workflows/` directory exists; builds/pushes run manually via `push.sh` / `build-push-docker.sh`.

---

## Code Conventions
- Most shell scripts start with `set -euo pipefail` (or at minimum `set -e`, matching existing scripts); `devcontainer/postCreate.sh` intentionally omits it because it relies on non-fatal best-effort steps. Quote all variable expansions. No `eval`.
- Run `shellcheck` on changed `.sh` files before committing. If shellcheck is not installed, run `bash -n <script>` as a fallback and state that shellcheck was unavailable.
- Validate Dockerfile changes with `docker build` for the affected file/stage. The build succeeding is the test.
- Keep pinned tool versions (the `# VERSION TRACKING` block in `Dockerfile`/`Dockerfile.base`) accurate when bumping a CLI.
- No secrets in source. `GITHUB_DAAX` and Docker Hub credentials come from the environment / `docker login`, never committed.

---

## Source Control
- Repo: `github.com/daax-dev/daax-devtools`. Default branch `main`.
- Never commit directly to `main`. All work lands via PR.
- Branch naming: `feature/`, `fix/`, `docs/`, `chore/`.
- Commits: imperative mood, present tense. Subject ≤ 72 characters. Body explains **why**.
- PR body must include: problem statement, approach, alternatives considered, validation evidence.
- Never merge your own PR unless explicitly authorized.
- Never commit secrets, tokens, keys, or `.env` files with live values.

---

## Definition of Done
A task is done only when:
- Changed shell scripts pass `shellcheck` (or `bash -n` if shellcheck is unavailable, noted explicitly).
- Changed Dockerfiles build successfully with `docker build`.
- PR opened with problem statement, approach, and validation evidence.
- No unresolved `[FILL IN]` placeholders in affected files. Explicitly-marked unknowns (documented gaps awaiting operator input, e.g. in `.claude/sourcecontrol.md`) are allowed and must state what is unknown and why.
- Decisions logged in `.logs/decisions/` if a non-trivial choice was made.
- Backlog.md task updated to Done with a link to the PR/commit.
