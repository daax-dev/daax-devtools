# Language Conventions

`[FILL IN]` marks a gap. Treat as "ask the operator," not a guess.

This repo's source is **shell scripts + Dockerfiles + JSON config**. No compiled/application language lives at the repo root (Go/Node/Python runtimes ship inside the built images, not in this repo). Only the blocks below apply.

For each active language, this file records: linter/formatter, validation, and style rules.

---

## Active Languages

### Shell (bash)
- Version target: bash 5.x (scripts use bashisms: `[[ ]]`, arrays, `BASH_SOURCE`).
- Preferred prologue: `set -euo pipefail` — at minimum `set -e`, matching existing scripts (`rebuild.sh`, `restart.sh` use `set -e`; `push.sh`, `build-push-docker.sh`, `rebuild-code-server.sh` use `set -euo pipefail`). Use `set -euo pipefail` for new scripts. Exception: `devcontainer/postCreate.sh` intentionally omits it because it relies on non-fatal `|| echo` best-effort steps (documented in its header).
- Linter: `shellcheck` (not vendored — install it). Run on every changed `.sh`. Fallback when unavailable: `bash -n <script>` (syntax only) and state that shellcheck was not run.
- Style: quote all expansions (`"$var"`), use `"$(...)"` not backticks, no `eval`. Validate version-tag / user input before use (see `validate_version_tag` in `build-push-docker.sh`).
- Keep scripts executable (`chmod +x`).

### Dockerfile
- Multi-arch (`linux/amd64,linux/arm64`); some stages depend on `TARGETARCH` build arg (e.g. `Dockerfile.code-server` hard-fails if unset).
- Pin tool versions via `ARG ...=x.y.z` and keep the `# VERSION TRACKING` comment block in `Dockerfile` / `Dockerfile.base` accurate when bumping a CLI.
- Use `--no-install-recommends` for apt installs; clean apt lists in the same layer.
- Validation: `docker build -f <file> devcontainer` must succeed. The build is the test.

### JSON (devcontainer.json, package.json, *.omp.json)
- Valid JSON / JSONC (devcontainer.json permits comments). Validate with `jq .` (strict JSON) or a JSONC-aware parser for devcontainer.json.
- `package.json` scripts are run with `bun`.

---

## Cross-Cutting Rules
- No language rule overrides the linter. Fix the config, not the code.
- No secrets in any script, Dockerfile, or JSON. Credentials (`GITHUB_DAAX`, Docker Hub) come from the environment.
- When bumping a pinned version, update the corresponding VERSION TRACKING comment in the same change.
