# Daax Development Container - Tools Layer
# Published to Docker Hub: jpoley/daax-agents
#
# This Dockerfile builds on the BASE layer (daax-agents-base) and adds:
# - AI coding assistant CLIs (Claude Code, Copilot, Codex, Gemini)
# - Task management (backlog.md, openspec)
# - Flowspec CLI
#
# The BASE layer contains stable dependencies (Python, Node, Go, dev tools).
# This TOOLS layer contains frequently-updated AI coding CLIs.
#
# Build order:
#   1. Build base: docker build -f Dockerfile.base -t jpoley/daax-agents-base .
#   2. Build tools: docker build -t jpoley/daax-agents .
#
# Usage:
#   docker pull jpoley/daax-agents:latest
#   Or reference in devcontainer.json: "image": "jpoley/daax-agents:latest"
#
# Automatic Rebuild Strategy:
#   - Base image: Rebuild monthly or when system deps change
#   - Tools image: Rebuild weekly or when AI CLIs release updates
#   - See .github/workflows/docker-publish.yml for automation
#
# =============================================================================
# VERSION TRACKING - Update these when upgrading AI CLI tools
# =============================================================================
# Last updated: 2026-02-21
# Flowspec: v0.4.004 (pinned)
# Backlog.md: backlog.md (latest - needs ignore-scripts=false for postinstall)
# Claude Code: @anthropic-ai/claude-code (latest)
# GitHub Copilot: @github/copilot (NEW - migrated from @githubnext/github-copilot-cli)
# OpenAI Codex: @openai/codex (latest)
# Google Gemini: @google/gemini-cli (latest)
# Agent Browser: agent-browser (latest)
# MCP Inspector: @modelcontextprotocol/inspector (latest) - for debugging MCP servers
# Kiro CLI: kiro-cli (latest) - AWS AI coding agent (curl installer)
# Get Shit Done: get-shit-done-cc (latest) - Meta-prompting system for Claude Code
# =============================================================================

# Use the base image with all stable dependencies
ARG BASE_IMAGE=jpoley/daax-agents-base:latest
FROM ${BASE_IMAGE}

# Re-establish environment (inherited from base but making explicit)
ENV PNPM_HOME="/home/vscode/.local/share/pnpm"
ENV GOPATH="/home/vscode/go"
ENV PATH="/home/vscode/.local/bin:${PNPM_HOME}:${GOPATH}/bin:/usr/local/bin:${PATH}"

# Copy custom oh-my-posh theme (in case base doesn't have it)
COPY --chown=vscode:vscode daax.omp.json /home/vscode/.config/daax.omp.json

# =============================================================================
# KIRO CLI (from AWS) - Uses dedicated installer
# =============================================================================
# Kiro CLI is installed via curl-based installer (not npm)
# See: https://kiro.dev/docs/cli/
#
# SECURITY: Checksum verification is REQUIRED.
# Unverified installer scripts are never executed to prevent supply-chain attacks.
#
# Build arguments:
#   KIRO_INSTALL_SHA256 - Required for installation (checksum of installer script)
#
# Usage:
#   docker build --build-arg KIRO_INSTALL_SHA256="<sha256>" ...
#
# To obtain the current checksum:
#   curl -fsSL https://cli.kiro.dev/install | sha256sum
#
# If no checksum is provided, Kiro CLI installation is skipped.
# There is intentionally NO bypass option - all remote installer scripts
# must be integrity-verified to prevent supply-chain attacks.
#
# IMPORTANT: When updating the checksum, verify the installer content has not been
# tampered with by reviewing diffs or checking against official Kiro announcements.
#
ARG KIRO_INSTALL_SHA256=""
# Note: Using 'set -eu' without 'pipefail' for POSIX sh compatibility.
# This RUN doesn't use pipes, so pipefail isn't needed anyway.
RUN set -eu; \
    if [ -n "${KIRO_INSTALL_SHA256}" ]; then \
      echo "Downloading Kiro CLI installer from https://cli.kiro.dev/install"; \
      curl -fsSL https://cli.kiro.dev/install -o /tmp/kiro-install.sh; \
      chmod +x /tmp/kiro-install.sh; \
      echo "Verifying checksum..."; \
      echo "${KIRO_INSTALL_SHA256}  /tmp/kiro-install.sh" | sha256sum -c -; \
      echo "Checksum verified."; \
      /tmp/kiro-install.sh && echo "Kiro CLI installed successfully" || echo "Warning: Kiro CLI installation failed (optional - requires Kiro account)"; \
      rm -f /tmp/kiro-install.sh; \
    else \
      echo "Note: Skipping Kiro CLI installation (no KIRO_INSTALL_SHA256 provided)"; \
      echo "      To install, provide --build-arg KIRO_INSTALL_SHA256=<checksum>"; \
    fi

# =============================================================================
# AI CODING ASSISTANT CLIs - This layer updates frequently
# =============================================================================
# Install AI coding assistant CLIs
# Note: These are optional, best-effort installs. Some packages may not be published yet.
# pnpm v10+ blocks build scripts by default; we allow them for native modules
# SECURITY: Package names verified against official sources (npm registry)
# See post-create.sh for runtime installation with package existence checks
# IMPORTANT: Configure pnpm global-bin-dir to avoid "not in PATH" errors
RUN pnpm config set global-bin-dir "${PNPM_HOME}" \
    && pnpm install -g @anthropic-ai/claude-code || echo "Note: Claude Code CLI not installed (optional - may require auth)" \
    && pnpm install -g @github/copilot || echo "Note: GitHub Copilot CLI not installed (optional - requires Copilot subscription)" \
    && pnpm install -g @openai/codex || echo "Note: OpenAI Codex CLI not installed (optional - requires ChatGPT subscription)" \
    && pnpm install -g @google/gemini-cli || echo "Note: Gemini CLI not installed (optional - package may not be published yet)" \
    && pnpm install -g opencode-ai || echo "Note: OpenCode CLI not installed (optional - package may not be published yet)" \
    && pnpm install -g agent-browser || echo "Note: Agent Browser not installed (optional)" \
    && pnpm install -g @modelcontextprotocol/inspector || echo "Note: MCP Inspector not installed (optional)" \
    && pnpm install -g get-shit-done-cc@1.9.13 || echo "Note: Get Shit Done not installed (optional)" \
    && pnpm approve-builds -g node-pty protobufjs tree-sitter-bash 2>/dev/null || echo "Note: pnpm approve-builds skipped (packages may not be installed)" \
    && pnpm rebuild -g 2>/dev/null || echo "Note: pnpm rebuild skipped (optional - some AI CLI packages may not be fully rebuilt)"

# =============================================================================
# TASK MANAGEMENT & SPEC-DRIVEN DEVELOPMENT
# =============================================================================
# Install task management and spec-driven development tools
# Note: Base image is now Debian (glibc), so no gcompat/musl workarounds needed
RUN pnpm install -g backlog.md \
    && echo "backlog.md installed successfully" \
    && backlog --version
USER vscode

# Install openspec (optional - may not be published)
RUN pnpm install -g @fission-ai/openspec || echo "openspec install skipped (optional)"

# Fix pnpm package vulnerabilities by forcing semver upgrade
# - CVE-2022-25883: semver@<7.5.2 -> >=7.5.2 (ReDoS vulnerability; fixed in semver 7.5.2)
RUN cd "${PNPM_HOME}" && pnpm update semver --latest 2>/dev/null || echo "pnpm semver update skipped"

# =============================================================================
# FLOWSPEC CLI (from GitHub)
# =============================================================================
# Install flowspec CLI from GitHub
# Note: 'flowspec' is a SEPARATE project (jpoley/flowspec) providing specification-driven development CLI.
# CRITICAL: Must succeed - this is an essential tool
RUN /home/vscode/.local/bin/uv tool install git+https://github.com/jpoley/flowspec.git@v0.4.004 \
    && echo "flowspec installed successfully" \
    && flowspec --version

# =============================================================================
# CACHE CLEANUP - Remove all build caches to minimize image size
# =============================================================================
RUN echo "=== Cleaning build caches ===" \
    # uv/pip: wheel cache, http cache, git checkouts
    && /home/vscode/.local/bin/uv cache clean \
    && rm -rf /home/vscode/.cache/uv 2>/dev/null || true \
    && rm -rf /home/vscode/.cache/pip 2>/dev/null || true \
    # pnpm: content-addressable store (already pruned, but ensure clean)
    && pnpm store prune 2>/dev/null || true \
    # npm: cache directory
    && npm cache clean --force 2>/dev/null || true \
    # General: temp files, logs, history
    && rm -rf /tmp/* 2>/dev/null || true \
    && rm -rf /home/vscode/.npm/_logs 2>/dev/null || true \
    && rm -rf /home/vscode/.local/state 2>/dev/null || true \
    && rm -f /home/vscode/.zsh_history 2>/dev/null || true \
    && rm -f /home/vscode/.bash_history 2>/dev/null || true \
    && echo "Cache cleanup complete"

# Labels for Docker Hub
LABEL org.opencontainers.image.title="Daax Agents"
LABEL org.opencontainers.image.description="Development container with AI coding assistants (Claude Code, Kiro, GSD, Codex, Gemini, GitHub Copilot) and task management tools"
LABEL org.opencontainers.image.source="https://github.com/jpoley/daax"
LABEL org.opencontainers.image.vendor="jpoley"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.base.name="jpoley/daax-agents-base:latest"

# Verify installations and print versions for debugging
# Note: Some CLIs may hang on --version, so we use timeout for safety:
# - Most AI CLIs (claude, copilot, codex, gemini, opencode) work fine with timeout
# - agent-browser and mcp-inspector are checked via 'which' because they may hang
#   or start interactive servers when run with --version
RUN echo "=== Tools Layer Installation Verification ===" \
    && echo "Python: $(python --version)" \
    && echo "Node: $(node --version)" \
    && echo "pnpm: $(pnpm --version)" \
    && echo "uv: $(/home/vscode/.local/bin/uv --version)" \
    && echo "flowspec: $(flowspec --version 2>&1 || echo 'not installed')" \
    && echo "--- AI Coding CLIs ---" \
    && echo "claude: $(timeout 5 claude --version 2>&1 || echo 'not installed')" \
    && echo "copilot: $(timeout 5 copilot --version 2>&1 || echo 'not installed')" \
    && echo "codex: $(timeout 5 codex --version 2>&1 || echo 'not installed')" \
    && echo "gemini: $(timeout 5 gemini --version 2>&1 || echo 'not installed')" \
    && echo "opencode: $(timeout 5 opencode --version 2>&1 || echo 'not installed')" \
    && echo "kiro: $(timeout 5 kiro-cli --version 2>&1 || echo 'not installed')" \
    && echo "agent-browser: $(which agent-browser >/dev/null 2>&1 && echo 'installed' || echo 'not installed')" \
    && echo "mcp-inspector: $(which mcp-inspector >/dev/null 2>&1 && echo 'installed' || echo 'not installed')" \
    && echo "gsd: $(which get-shit-done-cc >/dev/null 2>&1 && echo 'installed' || echo 'not installed')" \
    && echo "--- Task Management ---" \
    && echo "backlog: $(timeout 5 backlog --version 2>&1 || echo 'not installed')" \
    && echo "openspec: $(timeout 5 openspec --version 2>&1 || echo 'not installed')" \
    && echo "PATH: $PATH"

# Default command
CMD ["zsh"]
