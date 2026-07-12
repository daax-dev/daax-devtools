# Herdr Devcontainer Integration Plan

Date: 2026-07-06

## Goal

Add [Herdr](https://github.com/ogulcancelik/herdr) to every Daax devcontainer image that is used for AI coding agents, so users can run multiple coding sessions in the same container from either a web terminal or the CLI.

Herdr is a terminal-native agent multiplexer. The current upstream docs describe Linux/macOS stable binaries, `herdr --version`, `herdr server`, workspace/tab/pane/agent CLI commands, and official integrations for Claude Code, Codex, GitHub Copilot CLI, and OpenCode. The latest observed upstream release during planning is `v0.7.1` from 2026-06-24.

## Scope

Images and files that must be covered:

- `devcontainer/Dockerfile.core`: install Herdr in the shared AI CLI layer.
- `devcontainer/Dockerfile`: install Herdr in the standalone all-in-one image that currently builds directly from `daax-agents-base`.
- `devcontainer/Dockerfile.flowspec`, `devcontainer/Dockerfile.gsd`, `devcontainer/Dockerfile.openspec`: inherit Herdr from `Dockerfile.core`, and add verification/readme metadata so the contract is explicit.
- `devcontainer/lean/Dockerfile`: install and verify Herdr in the lean image. Validate Alpine/musl compatibility; if the upstream Linux binary is glibc-only, build Herdr from source in a throwaway Rust stage and copy the resulting binary.
- `devcontainer/Dockerfile.code-server`: add Herdr if this remains the web terminal image, or explicitly replace it with a documented web path that uses the same `jpoley/daax-agents` container.
- `devcontainer/postCreate.sh` and `devcontainer/lean/postCreate.sh`: idempotently install Herdr integrations for installed agents where runtime config directories exist.
- `devcontainer/README.md` and root `README.md`: document Herdr usage from terminal and web/code-server.
- `.github/workflows/docker-publish.yml` and `.github/actions/build-scan-push/action.yml`: ensure published images verify Herdr before push.

## Implementation Plan

1. Add a pinned, checksum-verified Herdr installer helper.
   - Prefer a local script such as `devcontainer/install-herdr.sh`.
   - Inputs: `HERDR_VERSION`, `HERDR_SHA256_AMD64`, `HERDR_SHA256_ARM64`.
   - Resolve `TARGETARCH` to upstream assets such as `herdr-linux-x86_64` and `herdr-linux-aarch64`.
   - Download from the GitHub release URL, verify SHA256, install to `/usr/local/bin/herdr`, and run `herdr --version`.
   - Do not use `curl | sh` in Dockerfiles.

2. Install Herdr in the correct image layers.
   - Add the helper invocation to `Dockerfile.core` so `core`, `flowspec`, `gsd`, and `openspec` all inherit it.
   - Add the same helper invocation to `Dockerfile` because it currently inherits from `daax-agents-base`, not `daax-agents-core`.
   - Add Herdr to `lean/Dockerfile` with a musl-specific validation path.
   - Add Herdr to `Dockerfile.code-server`, or retire/document that image as not being the supported web path.

3. Make runtime integrations reliable and non-destructive.
   - Ensure expected config directories exist before integration install:
     - Claude: `~/.claude` or `CLAUDE_CONFIG_DIR`.
     - Codex: `~/.codex` or `CODEX_HOME`.
     - Copilot: `~/.copilot` or `COPILOT_HOME`.
   - In `postCreate.sh`, run integration installs only when both `herdr` and the target agent command are available:
     - `herdr integration install claude`
     - `herdr integration install codex`
     - `herdr integration install copilot`
     - `herdr integration install opencode`
   - Keep integration failures non-fatal but visible, matching existing optional-agent behavior.
   - Add `herdr integration status` to verification output.

4. Expose the web workflow.
   - Document the supported browser path: code-server or VS Code Web terminal attached to the same container.
   - Confirm the web terminal and shell/CLI commands share the same Herdr server/socket state inside the container.
   - Include a user workflow for `herdr --session web-smoke`, split panes, launch multiple agents, detach, and reattach.

5. Update labels and docs.
   - Add `herdr` to `ai.daax.includes` labels where applicable.
   - Add a `ai.daax.versions.herdr` label for pinned images.
   - Add Herdr to the AI coding assistants table and common commands.
   - Document AGPL-3.0-or-later/commercial license status and confirm distribution compliance before publishing images with bundled Herdr.

## Validation Plan

### Static and Unit Checks

- Run repository tests:
  - `bun test`
  - any existing syntax or integration test scripts from `package.json`
- Confirm every Dockerfile that should include Herdr has a build-time verification line:
  - `herdr --version`
  - `command -v herdr`
- Confirm README mentions all supported paths:
  - CLI use.
  - Web/code-server terminal use.
  - Detach/reattach behavior.
  - Integration status command.

### Local Docker Smoke Tests

For each target image variant:

- Build the image locally for at least `linux/amd64`.
- Run:
  - `command -v herdr`
  - `herdr --version`
  - `herdr status || true`
  - `herdr server` in a background/supervised process, then `herdr status server`
  - `herdr session list --json`
  - `herdr workspace create --cwd /tmp --label smoke`
  - `herdr pane list`
  - `herdr integration status`
- Verify inherited variants:
  - `jpoley/daax-agents-core`
  - `jpoley/daax-agents`
  - `jpoley/daax-agents-flowspec`
  - `jpoley/daax-agents-gsd`
  - `jpoley/daax-agents-openspec`
  - `jpoley/daax-agents-lean`
  - `jpoley/daax-devcontainer` legacy alias after retag.

### End-to-End CLI Validation

Inside the same running devcontainer:

1. Start a named Herdr session:
   - `herdr --session cli-smoke`
2. From a second shell in the same container, inspect the running session:
   - `herdr session list --json`
   - `herdr pane list`
   - `herdr agent list`
3. Create multiple panes or agent processes using the Herdr CLI:
   - `herdr workspace create --cwd /workspaces/daax --label cli-smoke`
   - `herdr agent start codex-smoke --cwd /workspaces/daax -- echo codex-slot-ready`
   - `herdr agent start claude-smoke --cwd /workspaces/daax -- echo claude-slot-ready`
4. Read pane output with:
   - `herdr pane read <pane_id> --source recent --lines 20`
5. Stop the session cleanly:
   - `herdr session stop cli-smoke --json`

### End-to-End Web Validation

Using the supported web route attached to the same container:

1. Open the container in the browser via code-server or VS Code Web.
2. Open the integrated terminal and run:
   - `herdr --session web-smoke`
3. Use Herdr keybindings or mouse support to create multiple panes/tabs.
4. Launch at least two real installed agents when credentials are available:
   - `claude`
   - `codex`
   - `opencode`
   - `copilot`
5. Confirm Herdr shows agent identity/state and that `herdr agent list` from a separate terminal in the same container sees the same agents.
6. Detach from the web terminal, reconnect from another web terminal, and reattach to `web-smoke`.
7. Validate that a pane running a long-lived command survives detach/reattach.

### CI and Publish Gates

- The Docker publish workflow must fail before push if `herdr --version` fails in any image that should include Herdr.
- Docker Scout critical-CVE gating remains unchanged.
- Multi-arch builds must verify Herdr for both `linux/amd64` and `linux/arm64`.
- After push, pull each published image and run the same CLI smoke commands against the published tag.

## Acceptance Criteria

- Herdr is on `PATH` in every Daax AI coding devcontainer image and the supported web terminal image.
- Docker build verification fails if Herdr is missing or non-functional.
- Runtime post-create scripts install Herdr integrations for available supported agents without clobbering user auth/config.
- Users can run multiple agent panes in Herdr from a browser terminal and observe the same session from CLI commands in the same container.
- Detach/reattach works for both CLI and web terminal paths.
- Documentation explains install coverage, usage, integrations, and validation commands.
- License/compliance review for distributing bundled Herdr is recorded before publishing images.
