#!/bin/bash
# Daax Devcontainer Post-Create Script
# This script runs once when the container is first created
#
# Note: 'set -e' is intentionally NOT used here because this script employs
# non-fatal '|| echo' patterns for best-effort steps. This allows optional
# components (AI CLIs, hooks, etc.) to fail gracefully without blocking
# the entire devcontainer setup. Critical failures are handled explicitly.

echo "========================================"
echo "Daax Devcontainer Setup"
echo "========================================"
echo ""

# -----------------------------------------------------------------------------
# 0. Setup PATH for this script and future shells
# -----------------------------------------------------------------------------

# pnpm global packages install to PNPM_HOME, but the binaries/shims are created
# in PNPM_HOME itself when global-bin-dir is set to PNPM_HOME (done below)
PNPM_HOME="/home/vscode/.local/share/pnpm"
export PNPM_HOME

# Build the complete PATH we need
# Note: gt/bd binaries are pre-installed in /usr/local/bin via multi-stage build
export PATH="$PNPM_HOME:/home/vscode/.cargo/bin:/home/vscode/.local/bin:/usr/local/bin:$PATH"

# Create .zshenv for PATH (runs for ALL shells, including non-interactive)
# This ensures PATH is set even for VS Code integrated terminal
cat > /home/vscode/.zshenv << 'ZSHENV'
# Daax devcontainer PATH setup
# This file runs for ALL zsh shells (login, interactive, scripts)
# Note: gt/bd binaries are in /usr/local/bin (multi-stage build)

export PNPM_HOME="/home/vscode/.local/share/pnpm"
export PATH="$PNPM_HOME:/home/vscode/.cargo/bin:/home/vscode/.local/bin:/usr/local/bin:$PATH"

# Add Python venv to PATH (activation not needed, just PATH)
if [ -d "/workspaces/daax/.venv/bin" ]; then
    export PATH="/workspaces/daax/.venv/bin:$PATH"
    export VIRTUAL_ENV="/workspaces/daax/.venv"
fi
ZSHENV

# Also add to .zshrc for interactive features
cat >> /home/vscode/.zshrc << 'ZSHRC'

# Added by devcontainer setup (interactive shell additions)
# PATH is already set by .zshenv

# Activate Python virtual environment for prompt indicator
if [ -f "/workspaces/daax/.venv/bin/activate" ]; then
    source /workspaces/daax/.venv/bin/activate
fi

# Aliases for AI coding agents (YOLO modes)
# -----------------------------------------------------------------------------
# ⚠️  SECURITY WARNING: The following aliases bypass critical security features.
#
# These flags REMOVE ALL PERMISSION BARRIERS, allowing AI agents to:
# - Execute ANY shell command without approval
# - Read, modify, or delete ANY file on your system
# - Make network requests to any destination
# - Install packages and modify system configuration
#
# RISKS INCLUDE:
# - Malicious code execution from compromised prompts
# - Data exfiltration to external servers
# - Irreversible file deletion or corruption
# - Supply chain attacks through package installations
#
# ONLY USE IN: Isolated VMs/containers, offline environments, or CTF challenges.
# DO NOT USE: On production systems, with sensitive data, or in shared environments.
#
# Example CLI flags (subject to change; always verify in each tool's official docs):
# - Claude Code: --dangerously-skip-permissions
# - OpenAI Codex: --dangerously-bypass-approvals-and-sandbox
# - Gemini: --yolo
# - GitHub Copilot: No known YOLO flag; some setups use --allow-all-tools for broad tool permissions
#
# To enable, uncomment the desired alias below AT YOUR OWN RISK.
# -----------------------------------------------------------------------------
# alias claude-yolo='claude --dangerously-skip-permissions'
# alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'
# alias gemini-yolo='gemini --yolo'
# alias copilot-yolo='copilot --allow-all-tools'
ZSHRC

# -----------------------------------------------------------------------------
# 1. Python Environment Setup
# -----------------------------------------------------------------------------
echo "1. Setting up Python environment..."

# Only sync if .venv doesn't exist or pyproject.toml is newer
if [ ! -d "/workspaces/daax/.venv" ] || [ "pyproject.toml" -nt "/workspaces/daax/.venv" ]; then
    echo "   Installing Python dependencies with uv..."
    uv sync --all-extras
    echo "   Done."
else
    echo "   Python venv exists, skipping uv sync (delete .venv to force reinstall)"
fi

# Only install flowspec if not already available or if we want local dev version
if ! command -v flowspec &>/dev/null; then
    echo "   Installing flowspec CLI..."
    uv tool install . --force
    echo "   Done."
else
    echo "   flowspec already installed: $(flowspec --version 2>&1 || echo 'available')"
fi

# -----------------------------------------------------------------------------
# 2. AI Coding Assistant CLIs
# -----------------------------------------------------------------------------
echo ""
echo "2. Installing AI Coding Assistant CLIs..."

# Configure pnpm global bin
pnpm config set global-bin-dir "$PNPM_HOME"

# Helper function to safely install npm packages with existence verification
# Skips installation if command is already available (from Docker image)
# This prevents silent installation of typosquatted or non-existent packages
install_if_needed() {
    local pkg="$1"
    local cmd="$2"
    local display_name="$3"
    local note="$4"

    # Skip if command already exists (installed in Docker image)
    if command -v "$cmd" &>/dev/null; then
        echo "   $display_name already installed, skipping"
        return 0
    fi

    echo "   Installing ${display_name}..."
    if pnpm view "${pkg}" name >/dev/null 2>&1; then
        pnpm install -g "${pkg}" --prefer-offline || echo "   Note: ${display_name} install failed (optional - ${note})"
    else
        echo "   Skipping: ${pkg} not found in npm registry. Verify the official package name before enabling."
    fi
}

install_if_needed "@anthropic-ai/claude-code" "claude" "Claude Code CLI" "may require auth"
install_if_needed "@github/copilot" "copilot" "GitHub Copilot CLI" "requires Copilot subscription"
install_if_needed "@openai/codex" "codex" "OpenAI Codex CLI" "requires ChatGPT subscription"
install_if_needed "@google/gemini-cli" "gemini" "Google Gemini CLI" "package may not be published yet"
install_if_needed "opencode-ai" "opencode" "OpenCode CLI" "package may not be published yet"

# Kiro CLI uses curl installer (not npm)
# SECURITY: Checksum verification is REQUIRED by default.
# Unverified installer scripts are never executed to prevent supply-chain attacks.
#
# Environment variables:
#   KIRO_INSTALL_SHA256 - Required checksum for installer script
#
# If no checksum is provided, Kiro CLI installation is skipped.
# There is intentionally NO bypass option - all remote installer scripts
# must be integrity-verified to prevent supply-chain attacks.
#
# Prefer the Dockerfile installation for production where checksum can be pinned at build time.
if command -v kiro-cli &>/dev/null; then
    echo "   Kiro CLI already installed, skipping"
elif [ -n "${KIRO_INSTALL_SHA256:-}" ]; then
    echo "   Installing Kiro CLI (with checksum verification)..."
    KIRO_INSTALLER="/tmp/kiro-install.sh"
    if curl -fsSL https://cli.kiro.dev/install -o "$KIRO_INSTALLER"; then
        chmod +x "$KIRO_INSTALLER"
        echo "   Verifying Kiro installer checksum..."
        if echo "${KIRO_INSTALL_SHA256}  ${KIRO_INSTALLER}" | sha256sum -c - >/dev/null 2>&1; then
            echo "   Checksum verified."
            "$KIRO_INSTALLER" || echo "   Note: Kiro CLI install failed (optional - requires Kiro account)"
        else
            echo "   ERROR: Kiro installer checksum mismatch - skipping installation for security"
        fi
        rm -f "$KIRO_INSTALLER"
    else
        echo "   Note: Failed to download Kiro CLI installer (optional)"
    fi
else
    echo "   Skipping Kiro CLI installation (no KIRO_INSTALL_SHA256 provided)"
    echo "   To install, set KIRO_INSTALL_SHA256=<checksum>"
fi

# Get Shit Done - meta-prompting system for Claude Code
# SECURITY: Pinned version to reduce supply-chain risk (unpinned packages can be hijacked).
# To update: run `npm view get-shit-done-cc version` and update the version below.
install_if_needed "get-shit-done-cc@1.9.13" "get-shit-done-cc" "Get Shit Done (GSD)" "context engineering for Claude Code"

echo "   Done."

# -----------------------------------------------------------------------------
# 2.1. Herdr Agent Integrations
# -----------------------------------------------------------------------------
echo ""
echo "2.1. Setting up Herdr agent integrations..."

install_herdr_integration() {
    local agent="$1"
    local cmd="$2"
    local home_dir="${HOME:-/home/vscode}"
    local config_dir

    if ! command -v herdr >/dev/null 2>&1; then
        echo "   Herdr not installed, skipping ${agent} integration"
        return 0
    fi
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "   ${agent} command (${cmd}) not installed, skipping integration"
        return 0
    fi

    case "$agent" in
        claude)
            config_dir="${CLAUDE_CONFIG_DIR:-$home_dir/.claude}"
            mkdir -p "$config_dir/hooks"
            ;;
        codex)
            config_dir="${CODEX_HOME:-$home_dir/.codex}"
            mkdir -p "$config_dir"
            ;;
        copilot)
            config_dir="${COPILOT_HOME:-$home_dir/.copilot}"
            mkdir -p "$config_dir/hooks"
            ;;
        opencode)
            config_dir="${XDG_CONFIG_HOME:-$home_dir/.config}/opencode"
            mkdir -p "$config_dir/plugins"
            ;;
    esac

    echo "   Installing Herdr ${agent} integration..."
    herdr integration install "$agent" \
        || echo "   Warning: Herdr ${agent} integration install failed"
}

install_herdr_integration "claude" "claude"
install_herdr_integration "codex" "codex"
install_herdr_integration "copilot" "copilot"
install_herdr_integration "opencode" "opencode"

if command -v herdr >/dev/null 2>&1; then
    herdr integration status || echo "   Warning: Herdr integration status failed"
fi

# -----------------------------------------------------------------------------
# 2.5. Claude Logging Wrapper Setup
# -----------------------------------------------------------------------------
echo ""
echo "2.5. Setting up Claude logging wrapper..."

# Install node-pty for wrap.mjs (pinned version from package.json)
# Skip if node_modules already exists and has node-pty
if ! cd /workspaces/daax; then
    echo "   Warning: /workspaces/daax not found; skipping node-pty dependency install for Claude logging wrapper"
elif [ -d "node_modules/node-pty" ]; then
    echo "   node-pty already installed, skipping"
else
    echo "   Installing node-pty dependency..."
    # SECURITY: Prefer lockfile-based installs to ensure only audited pinned versions are installed
    if [ -f "pnpm-lock.yaml" ]; then
      # pnpm project with lockfile: use frozen lockfile install
      pnpm install --frozen-lockfile --prefer-offline || echo "   Warning: node-pty (Claude logging wrapper dependency) failed to install. The Claude logging wrapper may not work. Devcontainer setup will continue; you can retry later by running 'pnpm install --frozen-lockfile' in /workspaces/daax."
    elif [ -f "package-lock.json" ]; then
      # npm project with lockfile: use npm ci to respect package-lock.json
      npm ci || echo "   Warning: node-pty (Claude logging wrapper dependency) failed to install. The Claude logging wrapper may not work. Devcontainer setup will continue; you can retry later by running 'npm ci' in /workspaces/daax."
    else
      # No lockfile detected: fall back to standard pnpm install
      pnpm install --prefer-offline || echo "   Warning: node-pty (Claude logging wrapper dependency) failed to install. The Claude logging wrapper may not work. Devcontainer setup will continue; you can retry later by running 'pnpm install' in /workspaces/daax."
    fi
fi

# Create claude wrapper script
# Note: /usr/local/bin requires elevated privileges, using sudo explicitly
echo "   Creating claude wrapper..."
sudo tee /usr/local/bin/claude-wrapped > /dev/null << 'EOF'
#!/bin/bash
if [ "$DAAX_CAPTURE_TTY" = "true" ] && [ -f "/workspaces/daax/wrap.mjs" ]; then
  exec node /workspaces/daax/wrap.mjs claude "$@"
else
  exec claude "$@"
fi
EOF
sudo chmod +x /usr/local/bin/claude-wrapped

# Add alias to shell configs
echo "   Adding claude alias to shell configs..."
if ! grep -q "alias claude=" /home/vscode/.zshrc 2>/dev/null; then
  echo 'alias claude="claude-wrapped"' >> /home/vscode/.zshrc
fi

if ! grep -q "alias claude=" /home/vscode/.bashrc 2>/dev/null; then
  echo 'alias claude="claude-wrapped"' >> /home/vscode/.bashrc
fi

echo "   Done."

# -----------------------------------------------------------------------------
# 3. Task Management & Spec-Driven Development
# -----------------------------------------------------------------------------
echo ""
echo "3. Installing Task Management & Spec-Driven Development Tools..."

# Skip if already installed (from Docker image)
if command -v backlog &>/dev/null; then
    echo "   backlog.md already installed, skipping"
else
    echo "   Installing backlog.md CLI..."
    pnpm install -g backlog.md --prefer-offline || echo "   Warning: backlog.md install failed"
fi

if command -v openspec &>/dev/null; then
    echo "   OpenSpec already installed, skipping"
else
    echo "   Installing OpenSpec CLI..."
    install_if_needed "@fission-ai/openspec" "openspec" "OpenSpec CLI" "spec-driven development"
fi

echo "   Done."

# -----------------------------------------------------------------------------
# 4. MCP Server Configuration
# -----------------------------------------------------------------------------
echo ""
echo "4. Setting up MCP server configuration..."

mkdir -p /home/vscode/.config/claude

cat > /home/vscode/.config/claude/claude_desktop_config.json << EOF
{
  "mcpServers": {
    "backlog": {
      "command": "npx",
      "args": ["-y", "backlog.md"],
      "env": {
        "BACKLOG_DIR": "$PWD/backlog"
      }
    }
  }
}
EOF

echo "   MCP configuration created."

# -----------------------------------------------------------------------------
# 5. Git Hooks (if available)
# -----------------------------------------------------------------------------
echo ""
echo "5. Setting up git hooks..."

if [ -f ".claude/hooks/install-hooks.sh" ]; then
    bash .claude/hooks/install-hooks.sh || echo "   Warning: hook installation failed"
else
    echo "   No hooks to install."
fi

# -----------------------------------------------------------------------------
# 6. Make scripts executable
# -----------------------------------------------------------------------------
echo ""
echo "6. Making scripts executable..."

if [ -d "scripts/bash" ]; then
    chmod +x scripts/bash/*.sh 2>/dev/null || true
    echo "   Done."
else
    echo "   No scripts directory found."
fi

# -----------------------------------------------------------------------------
# 7. Verification
# -----------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Verification"
echo "========================================"
echo ""
echo "Python version:    $(python --version 2>&1)"
echo "uv version:        $(uv --version 2>&1)"
echo "Node version:      $(node --version 2>&1)"
echo "pnpm version:      $(pnpm --version 2>&1)"
echo "pnpm global bin:   $PNPM_HOME"
echo "gh version:        $(gh --version 2>&1 | head -1)"
echo ""

# Check for installed tools
echo "Installed CLI tools:"
command -v flowspec >/dev/null 2>&1 && echo "  - flowspec:    $(flowspec --version 2>&1 || echo 'installed')" || echo "  - flowspec:    NOT FOUND"
command -v claude >/dev/null 2>&1 && echo "  - claude:     $(claude --version 2>&1 || echo 'installed')" || echo "  - claude:     NOT FOUND"
command -v copilot >/dev/null 2>&1 && echo "  - copilot:     $(copilot --version 2>&1 || echo 'installed')" || echo "  - copilot:     NOT FOUND"
command -v codex >/dev/null 2>&1 && echo "  - codex:       installed" || echo "  - codex:       NOT FOUND"
command -v gemini >/dev/null 2>&1 && echo "  - gemini:      installed" || echo "  - gemini:      NOT FOUND"
command -v opencode >/dev/null 2>&1 && echo "  - opencode:    installed" || echo "  - opencode:    NOT FOUND"
command -v herdr >/dev/null 2>&1 && echo "  - herdr:       $(herdr --version 2>&1 || echo 'installed')" || echo "  - herdr:       NOT FOUND"
command -v kiro-cli >/dev/null 2>&1 && echo "  - kiro:        $(kiro-cli --version 2>&1 || echo 'installed')" || echo "  - kiro:        NOT FOUND"
command -v get-shit-done-cc >/dev/null 2>&1 && echo "  - gsd:         installed" || echo "  - gsd:         NOT FOUND"
command -v backlog >/dev/null 2>&1 && echo "  - backlog:     $(backlog --version 2>&1 || echo 'installed')" || echo "  - backlog:     NOT FOUND"
echo ""
echo "Multi-agent orchestration tools (pre-installed via multi-stage build):"
command -v gt >/dev/null 2>&1 && echo "  - gt (gastown):   $(gt version 2>&1 || echo 'installed')" || echo "  - gt (gastown):   NOT FOUND"
command -v bd >/dev/null 2>&1 && echo "  - bd (beads):     $(bd version 2>&1 || echo 'installed')" || echo "  - bd (beads):     NOT FOUND"
command -v openspec >/dev/null 2>&1 && echo "  - openspec:       $(openspec --version 2>&1 || echo 'installed')" || echo "  - openspec:       NOT FOUND"

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Quick start commands:"
echo "  pytest tests/           - Run test suite"
echo "  ruff check . --fix      - Lint and fix code"
echo "  ruff format .           - Format code"
echo "  backlog task list       - List backlog tasks"
echo "  flowspec --help         - Flowspec CLI"
echo "  claude                  - Claude Code CLI"
echo "  herdr                   - Multi-agent terminal workspace manager"
echo "  kiro-cli                - Kiro AI CLI (AWS)"
echo "  /gsd:help               - Get Shit Done (in Claude Code)"
echo ""
echo "Multi-agent orchestration:"
echo "  gt --help               - Gas Town (multi-agent orchestrator)"
echo "  bd --help               - Beads (git-backed issue tracker)"
echo "  openspec --help         - OpenSpec (spec-driven development)"
echo ""
echo "NOTE: Open a new terminal for PATH changes to take effect."
echo ""
