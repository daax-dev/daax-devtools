<!-- CLAUDE.md and AGENTS.md share the Operator Preferences and Hard Guardrails below. Keep them in sync. -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) and compatible agents working in this repository.

## Project
Name: daax-devtools
Purpose: Container, devcontainer, and deployment tooling for the Daax platform — builds and publishes the `daax-agents` AI-coding devcontainer images (Dockerfiles, devcontainer configs, build/push shell scripts).
Goal: Reproducible, multi-arch container images and devcontainer configs that build cleanly and publish to Docker Hub, kept in sync with daax-cli / daax-web requirements.

---

## Operator Preferences
<!-- Operator-specific. Revise or replace when applying to a different operator. -->
- State facts only. No sugarcoating.
- Surface problems, blockers, and risks immediately.
- Consult before one-way-door decisions and before any architectural change.
- Never answer from a guess. Validate claims against primary sources. If validation is not possible, say so explicitly.
- Objective language. No first-person pronouns. No apologies or hedges.

---

## Hard Guardrails (always apply)
- Plan before any non-trivial change. Write the plan down. Wait for approval.
- Never commit or merge directly to `main`.
- Never commit secrets, tokens, keys, or `.env` files with live values (e.g., `GITHUB_DAAX`, Docker Hub credentials).
- No destructive git (`reset --hard`, force-push, branch delete) without explicit operator approval.
- Never overwrite uncommitted user changes. Inspect existing patterns before editing.
- Run the formatter, linter, and validation after changes. There is no test suite — validation is `shellcheck` + `docker build` (see `.claude/workflow.md`). If validation is not possible, state exactly why.
- Log non-trivial decisions to `.logs/decisions/<topic>.jsonl`.
- Repo-local instructions override these template defaults.

---

## Required Reading
`.claude/workflow.md` is always loaded (see include below) — planning and definition of done apply to every task.

Read the matching file **before** you:
- write or edit code → `.claude/language.md` (shell + Dockerfile formatting, linting, validation)
- make an architectural or cross-boundary decision → `.claude/architecture.md`
- touch dependencies, runtime, or infrastructure → `.claude/stack.md`
- perform branch / PR / commit / merge operations → `.claude/sourcecontrol.md`
- write a decision or reference log entry → `.claude/history.md`

---

## Repository Map
| Path | Purpose |
|------|---------|
| `devcontainer/Dockerfile.base` | Foundation layer (`jpoley/daax-agents-base`): Python 3, Node 22, dev tools, oh-my-posh. Rebuild ~monthly. (Go is not here — only in `Dockerfile.code-server`.) |
| `devcontainer/Dockerfile` | Tools layer (`jpoley/daax-agents`): AI CLIs (Claude, Copilot, Codex, Gemini) on top of base. Rebuild ~weekly. |
| `devcontainer/Dockerfile.{core,flowspec,gsd,openspec,code-server}` | Specialized image variants. |
| `devcontainer/build-push-docker.sh` | 2-phase multi-arch build+push to Docker Hub (base + tools). |
| `devcontainer/build-all.sh` | Build all Dockerfile variants. |
| `devcontainer/{postCreate.sh,prebuild.sh}` | Devcontainer lifecycle hooks. |
| `devcontainer/{lean,starter-app}/` | Lean (Alpine) and starter-template devcontainer variants. |
| `devcontainer/devcontainer.json` | VS Code devcontainer config. |
| `push.sh` / `rebuild.sh` / `rebuild-code-server.sh` / `restart.sh` | Root container management scripts. |
| `scripts/contain-claude.sh` | Helper to run Claude inside the devcontainer. |
| `package.json` | npm metadata + `agents:build|push|release` scripts (run with `bun`). |
| `backlog/` | Backlog.md task-tracking config (system of record). |

## Key Commands
```bash
./rebuild.sh                       # Build daax-agents image locally
./push.sh                          # Build + push tools image to Docker Hub
./push.sh --tag v1.0.0             # Push with a version tag
./restart.sh                       # Restart the running daax container
cd devcontainer && ./build-push-docker.sh        # Build+push tools (cached base)
cd devcontainer && ./build-push-docker.sh --base # Rebuild base layer first
cd devcontainer && ./build-all.sh                # Build all variants
bun run agents:release             # package.json: build + push :latest
```

---

<!-- BACKLOG.MD MCP GUIDELINES START -->

<CRITICAL_INSTRUCTION>

## BACKLOG WORKFLOW INSTRUCTIONS

This project uses Backlog.md (MCP) for all task and project management activities. It is the system of record for work intake.

**CRITICAL GUIDANCE**

- If your client supports MCP resources, read `backlog://workflow/overview` to understand when and how to use Backlog for this project.
- If your client only supports tools or the above request fails, call `backlog.get_workflow_overview()` tool to load the tool-oriented overview.

</CRITICAL_INSTRUCTION>

<!-- BACKLOG.MD MCP GUIDELINES END -->

@.claude/workflow.md
