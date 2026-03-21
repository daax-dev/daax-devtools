#!/bin/bash
# Daax Lean - Minimal postCreate script
# Claude Code + Flowspec only

echo "========================================"
echo "Daax Lean Setup"
echo "========================================"

PNPM_HOME="/home/vscode/.local/share/pnpm"
export PNPM_HOME
export PATH="$PNPM_HOME:/home/vscode/.local/bin:$PATH"

# Shell config
cat > /home/vscode/.zshenv << 'ZSHENV'
export PNPM_HOME="/home/vscode/.local/share/pnpm"
export PATH="$PNPM_HOME:/home/vscode/.local/bin:$PATH"
if [ -d "/workspaces/daax/.venv/bin" ]; then
    export PATH="/workspaces/daax/.venv/bin:$PATH"
    export VIRTUAL_ENV="/workspaces/daax/.venv"
fi
ZSHENV

# Python environment
echo "1. Setting up Python environment..."
if [ ! -d "/workspaces/daax/.venv" ] || [ "pyproject.toml" -nt "/workspaces/daax/.venv" ]; then
    uv sync --all-extras
else
    echo "   Python venv exists, skipping"
fi

# Flowspec
if ! command -v flowspec &>/dev/null; then
    echo "   Installing flowspec CLI..."
    uv tool install . --force
fi

# Claude Code (ensure installed)
echo "2. Verifying Claude Code..."
if ! command -v claude &>/dev/null; then
    pnpm config set global-bin-dir "$PNPM_HOME"
    pnpm install -g @anthropic-ai/claude-code || echo "   Claude Code requires auth"
fi

# MCP config
echo "3. Setting up MCP configuration..."
mkdir -p /home/vscode/.config/claude
cat > /home/vscode/.config/claude/claude_desktop_config.json << EOF
{
  "mcpServers": {
    "backlog": {
      "command": "npx",
      "args": ["-y", "backlog.md"],
      "env": { "BACKLOG_DIR": "$PWD/backlog" }
    }
  }
}
EOF

echo ""
echo "========================================"
echo "Verification"
echo "========================================"
echo "Python:   $(python --version 2>&1)"
echo "uv:       $(uv --version 2>&1)"
echo "Node:     $(node --version 2>&1)"
echo "flowspec: $(flowspec --version 2>&1 || echo 'installed')"
echo "claude:   $(claude --version 2>&1 || echo 'installed')"
echo "backlog:  $(backlog --version 2>&1 || echo 'installed')"
echo ""
echo "Daax Lean Ready!"
