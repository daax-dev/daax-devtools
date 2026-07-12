---
id: TASK-001
title: Add Herdr to all AI coding devcontainer images
status: Done
assignee: []
created_date: '2026-07-06 22:49'
labels:
  - devcontainer
  - ai-agents
dependencies: []
references:
  - 'https://github.com/ogulcancelik/herdr/releases/tag/v0.7.1'
documentation:
  - docs/herdr-devcontainer-integration-plan.md
  - 'https://github.com/ogulcancelik/herdr'
  - 'https://herdr.dev/docs/install/'
  - 'https://herdr.dev/docs/integrations/'
  - 'https://herdr.dev/docs/cli-reference/'
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add Herdr to every Daax devcontainer image used for AI coding agents so users can run multiple coding sessions in the same container from either a web terminal or CLI. The implementation plan is documented in docs/herdr-devcontainer-integration-plan.md and should be kept in sync with the GitHub issue. Key context: Herdr is a terminal-native agent multiplexer with Linux/macOS stable binaries, CLI/server commands, and official integrations for Claude Code, Codex, GitHub Copilot CLI, and OpenCode. The current Daax image graph has core/all-in-one/flowspec/gsd/openspec/lean/code-server paths, so install coverage must be explicit rather than assumed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Herdr is installed on PATH in every Daax AI coding devcontainer image and in the supported web terminal image/path.
- [x] #2 Docker build verification fails when Herdr is missing or non-functional in an image that should include it.
- [x] #3 Herdr install is pinned and integrity-verified, or built from source where binary compatibility requires it.
- [x] #4 Post-create scripts idempotently install Herdr integrations for available supported agents without clobbering user auth/config.
- [x] #5 CLI end-to-end validation proves multiple Herdr sessions/panes can be created, inspected, read, and stopped in the same container.
- [x] #6 Web terminal end-to-end validation proves multiple coding sessions can run through Herdr and can be inspected by CLI commands in the same container.
- [x] #7 Documentation covers usage, integrations, detach/reattach, web terminal workflow, validation commands, and license/compliance notes.
<!-- AC:END -->

## Completion Notes

- Implemented pinned Herdr v0.7.1 installation with SHA256 verification for amd64 and arm64.
- Added build-time and runtime verification through `daax-verify-herdr`.
- Published multi-arch Docker Hub tags for core, agents, flowspec, gsd, openspec, lean, code-server, and the legacy devcontainer alias.
- Verified every published tag with `daax-verify-herdr runtime`.
