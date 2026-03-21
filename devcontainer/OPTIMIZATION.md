# Devcontainer Build Optimization Suggestions

## Essential (Keep)
- **Claude Code CLI** - primary AI coding tool
- **Flowspec CLI** - spec-driven development (main purpose)
- **Python + uv** - required for flowspec
- **Node.js + pnpm** - required for Claude Code

---

## Layer 1: Base Image (`Dockerfile.base`)

| Item | Lines | Est. Size | Recommendation |
|------|-------|-----------|----------------|
| Go runtime | 42 | ~250MB | Remove if not using gastown/beads |
| gastown (gt) | 139 | ~20MB | Remove - optional multi-agent tool |
| beads (bd) | 140 | ~15MB | Remove - optional issue tracker |
| neovim | 48 | ~40MB | Remove - VS Code is primary editor |
| lazygit | 49 | ~15MB | Remove - use VS Code GitLens |
| btop | 45 | ~5MB | Remove - system monitor not needed |
| asciinema | 49 | ~3MB | Remove - terminal recording rarely used |
| oh-my-posh | 113-127 | ~20MB | Remove - fancy prompt not essential |
| claude-code-transcripts | 145 | ~5MB | Remove if not using transcript export |
| tmux | 44 | ~2MB | Keep - useful for terminal multiplexing |
| fzf | 46 | ~1MB | Keep - useful for fuzzy finding |
| GitHub CLI | 58-76 | ~50MB | Keep - useful for PRs/issues |

**Base Layer Potential Savings: ~425MB**

---

## Layer 2: Tools Image (`Dockerfile`)

| Item | Lines | Est. Size | Recommendation |
|------|-------|-----------|----------------|
| @github/copilot | 57 | ~80MB | Remove - requires paid subscription |
| @openai/codex | 58 | ~60MB | Remove - requires ChatGPT Plus |
| @google/gemini-cli | 59 | ~50MB | Remove - may not even be published |
| opencode-ai | 60 | ~40MB | Remove - optional alternative |
| @fission-ai/openspec | 69 | ~20MB | Optional - keep if using OpenSpec |
| backlog.md | 68 | ~15MB | Keep - task management |

**Tools Layer Potential Savings: ~230MB**

---

## Layer 3: devcontainer.json (Runtime)

| Item | Lines | Est. Time | Recommendation |
|------|-------|-----------|----------------|
| common-utils feature | 27-36 | ~30-60s | Remove - duplicates base image setup |
| code-spell-checker ext | 50 | ~5s | Remove - nice-to-have |
| markdown-all-in-one ext | 46 | ~3s | Remove - if not editing markdown |
| errorlens ext | 49 | ~2s | Remove - nice-to-have |

**Runtime Potential Savings: ~40-70 seconds per container start**

---

## Layer 4: postCreate.sh (Runtime)

| Item | Lines | Est. Time | Recommendation |
|------|-------|-----------|----------------|
| AI CLI re-checks | 117-152 | ~20s | Simplify - tools already in image |
| node-pty install | 161-179 | ~15s | Keep - needed for Claude wrapper |

**Runtime Potential Savings: ~20 seconds**

---

## Summary

| Layer | Potential Savings |
|-------|-------------------|
| Base Image | ~425MB |
| Tools Image | ~230MB |
| Container Start | ~60-90 seconds |
| **Total Image Size** | **~655MB smaller** |

---

## Minimum Viable Trimmed Config

Keep only:
- Python 3.13 + uv
- Node.js + pnpm
- Claude Code CLI
- Flowspec CLI
- backlog.md
- GitHub CLI
- tmux, fzf
- Basic shell (zsh)

---

## CVE Dependency Graph

### OLD (before multi-stage build)
```
Layer 6 (Go Toolchain) - REMOVED
├── apk add go (Alpine Go 1.24.11)
│   └── golang.org/x/crypto v0.30.0  ← VULNERABLE
```

### NEW (multi-stage build - IMPLEMENTED)
```
Builder Stage (golang:1.25-alpine) - NOT in final image
├── golang.org/x/crypto v0.39.0  ← FIXES CVE-2025-22869
├── go install gastown/gt → binary copied to final
└── go install beads/bd → binary copied to final

Final Image (dhi.io/python:3.13-alpine3.22-dev)
├── /usr/local/bin/gt  (static binary, ~15MB)
├── /usr/local/bin/bd  (static binary, ~20MB)
└── NO Go toolchain (~250MB saved)

Layer 13 (GitHub CLI) - unchanged
├── gh (v2.83.2)
│   └── CVE-2024-52308 (fix: 2.62.0) - likely false positive
```

### Root Cause Analysis (2026-01-14)

**Layer 6 CVEs were from Alpine's Go package, NOT gastown/beads!**

Investigation steps:
1. Forked and ran `go get -u ./...` on both repos
2. Verified NO x/crypto or logrus in either go.sum
3. Found x/crypto v0.30.0 **vendored inside Alpine's Go 1.24 toolchain**

**Solution**: Multi-stage build using Go 1.25 (has x/crypto v0.39.0)
- Fixes CVE-2025-22869 (needs ≥0.35.0) ✅
- CVE-2025-47913 still present (needs ≥0.43.0) - wait for Go 1.26

### Upstream Issue Status

| Package | CVE | Status |
|---------|-----|--------|
| **Alpine Go 1.24** | CVE-2025-47913, CVE-2025-22869 | ⚠️ Mitigated via multi-stage (Go 1.25) |
| **Go 1.25** | CVE-2025-47913 | ⚠️ Still present (needs Go 1.26 for x/crypto ≥0.43.0) |
| steveyegge/gastown | N/A | ✅ Not the source |
| steveyegge/beads | N/A | ✅ Not the source |
| cli/cli (GitHub CLI) | CVE-2024-52308 | ✅ gh 2.83.2 > fix 2.62.0 |

### Recommended Actions

1. ✅ **IMPLEMENTED: Multi-stage build** (Dockerfile.base)
   - Go 1.25 builder stage compiles gt/bd binaries
   - Final image has NO Go toolchain (~250MB saved)
   - x/crypto v0.39.0 (fixes CVE-2025-22869)
   - CVE-2025-47913 still present (needs ≥0.43.0) - wait for Go 1.26

2. **Use lean devcontainer** → No Go binaries at all (`.devcontainer/lean/`)

3. **Layer 13 CVEs** - gh 2.83.2 > fix version 2.62.0 (likely scanner false positive)

---

## Lean Devcontainer

A minimal devcontainer without Go tools is available at:

```
.devcontainer/lean/
├── Dockerfile
├── devcontainer.json
└── postCreate.sh
```

To use: Open VS Code Command Palette → "Dev Containers: Open Folder in Container" → Select `.devcontainer/lean/`
