<!-- CLAUDE.md and AGENTS.md share the Operator Preferences and Hard Guardrails below. Keep them in sync. -->

# AGENTS.md

Entry point for OpenAI Codex and compatible agents.

---

## Project
Name: daax-devtools
Purpose: Container, devcontainer, and deployment tooling for the Daax platform — builds and publishes the `daax-agents` AI-coding devcontainer images (Dockerfiles, devcontainer configs, build/push shell scripts).

---

## Operator Preferences
<!-- Operator-specific. Revise or replace when applying to a different operator. -->
- State facts only. No sugarcoating.
- Surface problems, blockers, and risks immediately.
- Consult before one-way-door decisions and before any architectural change.
- Never guess. If validation is not possible, say so explicitly.
- Objective language. No first-person pronouns. No apologies or hedges.

---

## Hard Guardrails (always apply)
- Plan before any non-trivial change. Write the plan down. Wait for approval.
- Never commit or merge directly to `main`.
- Never commit secrets, tokens, keys, or `.env` files with live values (e.g., `GITHUB_DAAX`, Docker Hub credentials).
- No destructive git (`reset --hard`, force-push, branch delete) without explicit operator approval.
- Never overwrite uncommitted user changes. Inspect existing patterns before editing.
- Run the formatter, linter, and validation after changes. No test suite exists — validation is `shellcheck` + `docker build` (see `.claude/workflow.md`). If validation is not possible, state exactly why.
- Log non-trivial decisions to `.logs/decisions/<topic>.jsonl`.
- Repo-local instructions override these template defaults.

---

## Required Reading
`.claude/workflow.md` — planning and definition of done — applies to every task. Read it before starting work.

Read the matching file **before** you:
- write or edit code → `.claude/language.md` (shell + Dockerfile formatting, linting, validation)
- make an architectural or cross-boundary decision → `.claude/architecture.md`
- touch dependencies, runtime, or infrastructure → `.claude/stack.md`
- perform branch / PR / commit / merge operations → `.claude/sourcecontrol.md`
- write a decision or reference log entry → `.claude/history.md`

---

## Repository Map
- `devcontainer/Dockerfile.base` — base layer (`jpoley/daax-agents-base`): Python 3, Node 22, dev tools. (Go is not in base/tools images — only in `Dockerfile.code-server`.)
- `devcontainer/Dockerfile` — tools layer (`jpoley/daax-agents`): AI CLIs on top of base.
- `devcontainer/Dockerfile.{core,flowspec,gsd,openspec,code-server}` — specialized variants.
- `devcontainer/build-push-docker.sh` — 2-phase multi-arch build+push to Docker Hub.
- `devcontainer/build-all.sh` — build all Dockerfile variants.
- `devcontainer/{postCreate.sh,prebuild.sh,devcontainer.json}` — devcontainer lifecycle + config.
- `devcontainer/{lean,starter-app}/` — lean (Alpine) and starter-template variants.
- `push.sh` / `rebuild.sh` / `rebuild-code-server.sh` / `restart.sh` — root container scripts.
- `scripts/contain-claude.sh` — helper to run Claude inside the devcontainer.
- `package.json` — npm metadata + `agents:build|push|release` scripts (run with `bun`).
- `backlog/` — Backlog.md task-tracking config (system of record).

## Task Management
This project uses Backlog.md as the system of record. If MCP resources are supported, read `backlog://workflow/overview`; otherwise call `backlog.get_workflow_overview()`.
