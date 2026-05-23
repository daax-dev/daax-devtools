# Daax Dev Container

Development container for consistent, reproducible development environments across all machines.

## Quick Start

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed
- [VS Code](https://code.visualstudio.com/) with [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- Git configured with your credentials

### First Time Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/jpoley/daax
   cd daax
   ```

2. **Open in VS Code**:
   ```bash
   code .
   ```

3. **Reopen in Container**:
   - VS Code will prompt: "Reopen in Container"
   - Click "Reopen in Container"
   - Wait ~2-3 minutes for initial setup

4. **Verify Environment**:
   ```bash
   flowspec --version
   pytest tests/
   backlog task list
   ```

## Authentication

### Subscription-Based Tools (OAuth)

These tools use **subscription-based authentication** via browser OAuth, NOT API keys:

| Tool | Auth Method | First-Time Setup |
|------|-------------|------------------|
| **Claude Code** | Claude Pro/Max subscription | Run `claude` → Opens browser for OAuth |
| **GitHub Copilot** | Copilot Pro/Business subscription | Run `copilot` → `/login` → Opens browser |

#### First-Time Authentication (Inside Container)

**Claude Code:**
```bash
# Run claude - it will open your browser for OAuth
claude

# Follow the browser prompts to sign in with your Claude Pro/Max account
# Once authenticated, you're ready to use Claude Code
```

**GitHub Copilot:**
```bash
# Run copilot CLI
copilot

# Type /login to authenticate
/login

# Follow the browser prompts to sign in with your GitHub account
# (Requires Copilot Pro, Pro+, Business, or Enterprise subscription)
```

#### Token Persistence Across Container Rebuilds

Your OAuth tokens are persisted via volume mounts from your **host machine**:

| Tool | Host Path | Container Path |
|------|-----------|----------------|
| Claude Code | `~/.claude` | `/home/vscode/.claude` |
| GitHub Copilot | `~/.config/github-copilot` | `/home/vscode/.config/github-copilot` |

**This means:**
- You only authenticate **once per host machine**
- Tokens survive container rebuilds
- If you auth on muckross, you need to auth again on galway (different host)
- No API keys needed - subscriptions are tied to your account

### API-Key Based Tools

These tools use traditional API keys (set in your host environment):

```bash
# Required for GitHub operations (backlog, gh CLI)
export GITHUB_TOKEN="ghp_..."

# Optional: For API-based AI CLIs
export OPENAI_API_KEY="sk-..."      # For codex CLI
export GOOGLE_API_KEY="..."          # For gemini CLI
```

The devcontainer automatically forwards these to the container.

## Dockerfile Variants

The devcontainer directory contains multiple Dockerfile variants for different use cases:

| Dockerfile | Image Name | Base | Key Features | When to Use |
|------------|------------|------|--------------|-------------|
| `Dockerfile.base` | `daax-agents-base` | `node:22-bookworm-slim` | Python 3.x, Node.js 22, pnpm, uv, gh CLI, oh-my-posh, tmux, neovim, btop, fzf, asciinema, ruff, pytest | Never directly - this is the foundation layer |
| `Dockerfile.core` | `daax-agents-core` | `daax-agents-base` | All AI CLIs (Claude, Copilot, Codex, Gemini, OpenCode, Kiro), Agent Browser, MCP Inspector | When you only need AI coding assistants without task frameworks |
| `Dockerfile` | `daax-agents` | `daax-agents-base` | AI CLIs + Flowspec + Backlog.md + OpenSpec + GSD (all-in-one) | Full-featured default image with all tools |
| `Dockerfile.flowspec` | `daax-agents-flowspec` | `daax-agents-core` | Core + Flowspec CLI + Backlog.md | Specification-driven development with task management |
| `Dockerfile.gsd` | `daax-agents-gsd` | `daax-agents-core` | Core + get-shit-done-cc | Task execution framework for Claude Code |
| `Dockerfile.openspec` | `daax-agents-openspec` | `daax-agents-core` | Core + @fission-ai/openspec | Fission AI's specification framework |
| `lean/Dockerfile` | `daax-lean` | `dhi.io/python:3.13-alpine3.22-dev` | Claude Code + Flowspec + Backlog.md + ruff/pytest (no Go tools) | Minimal image with reduced CVE surface (~1GB smaller) |

### Image Hierarchy

```
node:22-bookworm-slim
    └── Dockerfile.base (daax-agents-base)
            ├── Dockerfile (daax-agents) [default - all tools in one]
            └── Dockerfile.core (daax-agents-core)
                    ├── Dockerfile.flowspec (daax-agents-flowspec)
                    ├── Dockerfile.gsd (daax-agents-gsd)
                    └── Dockerfile.openspec (daax-agents-openspec)

dhi.io/python:3.13-alpine3.22-dev (Alpine-based, separate tree)
    └── lean/Dockerfile (daax-lean)
```

### Target Image Sizes

| Variant | Approximate Size |
|---------|------------------|
| base | ~800MB |
| core | ~1.4GB |
| default (daax-agents) | ~2.0GB |
| flowspec | ~1.8GB |
| gsd | ~1.5GB |
| openspec | ~1.5GB |
| lean | ~600MB |

## What's Included

### Python Environment

- **Python 3.x** (system Python from Debian bookworm-slim; lean variant uses [Docker Hardened Image](https://docs.docker.com/dhi/))
- **uv** - Fast Python package manager
- **ruff** - Linter and formatter
- **pytest** - Test framework

### AI Coding Assistants

| Tool | Command | Auth Type | Subscription Required |
|------|---------|-----------|----------------------|
| Claude Code | `claude` | OAuth (browser) | Claude Pro/Max |
| GitHub Copilot | `copilot` | OAuth (browser) | Copilot Pro/Business |
| [Kiro](https://kiro.dev/) | `kiro-cli` | OAuth (browser) | Kiro Free/Pro |
| [OpenAI Codex](https://platform.openai.com/docs/overview) | `codex` | OAuth or API Key | ChatGPT Plus/Pro/Team or OpenAI API |
| Google Gemini | `gemini` | API Key | Google AI API |
| [OpenCode](https://github.com/opencode-ai/opencode) | `opencode` | API Key | OpenAI/Anthropic API |
| [Get Shit Done](https://github.com/glittercowboy/get-shit-done) | `gsd:*` | None (uses Claude Code) | Claude Code required |

### Task Management

| Tool | Command | Description |
|------|---------|-------------|
| backlog.md | `backlog` | Task management CLI |
| flowspec | `flowspec` | Flowspec CLI |

### Debugging Tools

| Tool | Command | Description |
|------|---------|-------------|
| [MCP Inspector](https://github.com/modelcontextprotocol/inspector) | `npx @modelcontextprotocol/inspector` | Debug and test MCP servers |
| [Agent Browser](https://github.com/nicholasoxford/agent-browser) | `npx agent-browser` | Browser automation for AI agents |

### VS Code Extensions

- Python + Pylance
- Ruff (linter/formatter)
- TOML support
- YAML support
- Markdown support
- Docker support
- GitLens
- Error Lens
- Spell Checker

## Container Lifecycle

```
Start Container
│
├─→ onCreateCommand (once)
│   └─ Install uv package manager
│
├─→ postCreateCommand (once)
│   ├─ uv sync (install Python dependencies)
│   ├─ Install flowspec CLI
│   ├─ Install AI coding assistants (claude, copilot, codex, gemini)
│   ├─ Install backlog.md CLI
│   └─ Setup MCP server configuration
│
├─→ postStartCommand (every start)
│   └─ Git safe directory configuration
│
└─→ postAttachCommand (every attach)
    └─ Display environment info

Ready for Development!
```

## Volume Mounts

| Host Path | Container Path | Purpose | Mode |
|-----------|---------------|---------|------|
| `./backlog/` | `/workspaces/daax/backlog/` | Task persistence | Read-Write |
| `~/.gitconfig` | `/home/vscode/.gitconfig-host` | Git configuration (copied to `/home/vscode/.gitconfig` on start) | Read-Only |
| `~/.ssh/` | `/home/vscode/.ssh/` | SSH keys | Read-Only |
| `~/.claude/` | `/home/vscode/.claude/` | Claude config | Read-Write |

## Common Commands

```bash
# Development
pytest tests/              # Run tests
ruff check . --fix         # Lint and fix
ruff format .              # Format code
uv sync                    # Update dependencies

# Task Management
backlog task list          # List tasks
backlog task create "..."  # Create task
flowspec workflow validate # Validate workflow

# AI Assistants
claude --help              # Claude Code CLI
copilot --help             # GitHub Copilot
kiro-cli --help            # Kiro CLI (AWS)
opencode --help            # OpenCode CLI
/gsd:help                  # Get Shit Done (in Claude Code)

# Debugging Tools
npx @modelcontextprotocol/inspector  # Debug MCP servers
npx agent-browser                    # Browser automation
```

## Troubleshooting

### Container Won't Start

**Symptom**: "Failed to start container"

**Solutions**:
1. Ensure Docker Desktop is running
2. Try rebuilding: Command Palette → "Dev Containers: Rebuild Container"
3. Check Docker has enough resources (4GB+ RAM recommended)

### uv Command Not Found

**Symptom**: `bash: uv: command not found`

**Solution**:
```bash
# Reload PATH
source ~/.bashrc

# Or reinstall uv
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### flowspec Command Not Found

**Symptom**: `bash: flowspec: command not found`

**Solution**:
```bash
# Reinstall flowspec CLI
uv tool install . --force

# Verify installation
which flowspec
flowspec --version
```

### AI CLI Not Working

**Symptom**: CLI installed but not responding

**Solutions**:
1. For Claude Code, check that you are authenticated via OAuth (see `~/.claude/` directory for your token files).
2. For Codex CLI or other API-based tools, check the appropriate API key is set (e.g., `echo $OPENAI_API_KEY`).
3. Reinstall the CLI: `pnpm install -g @anthropic-ai/claude-code`
4. Check pnpm global bin is in PATH

### Tests Fail in Container

**Symptom**: Tests pass locally but fail in container

**Solution**:
```bash
# Check Python version
python --version  # Should be 3.13.x

# Force dependency sync
uv sync --force

# Check environment variables
env | grep -E "GITHUB_|ANTHROPIC_"
```

## Customization

### Adding VS Code Extensions

Edit `.devcontainer/devcontainer.json`:

```json
{
  "customizations": {
    "vscode": {
      "extensions": [
        "your-extension-id-here"
      ]
    }
  }
}
```

### Adding System Packages

Use devcontainer features in `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {}
  }
}
```

### Local Overrides

For personal customizations that shouldn't be committed, create a `.devcontainer/devcontainer.local.json`:

```json
{
  "remoteEnv": {
    "MY_LOCAL_VAR": "value"
  }
}
```

## Multi-Machine Consistency

This devcontainer guarantees identical environments across all machines:

| Machine | Environment |
|---------|-------------|
| muckross | Identical |
| galway | Identical |
| kinsale | Identical |
| adare | Identical |

**No manual synchronization required**:

```bash
# On any machine
git pull
# VS Code: Command Palette → "Dev Containers: Rebuild Container"
# Result: Guaranteed identical to all other machines
```

This directly addresses the CLAUDE.md repeatability mandate.

## Speeding Up Devcontainer Startup

By default, the devcontainer uses `jpoley/daax-agents:latest` + features, which requires applying features at container creation. For faster startup, you can use a **prebuilt image** with all features baked in.

### Option 1: Prebuild with devcontainer CLI (Recommended)

```bash
# Install devcontainer CLI if needed
npm install -g @devcontainers/cli

# Build and push prebuilt image (includes all features)
.devcontainer/prebuild.sh --push

# Then update devcontainer.json:
# 1. Change image to: "jpoley/daax-devcontainer:latest"
# 2. Comment out the "features" block
```

### Option 2: Pre-pull base image

```bash
# Pull the image ahead of time so startup doesn't wait for download
docker pull jpoley/daax-agents:latest
```

### Startup Time Comparison

| Configuration | First Start | Subsequent Start |
|---------------|-------------|------------------|
| Base + Features | ~2-3 min | ~30-60 sec |
| Prebuilt Image | ~30-60 sec | ~10-20 sec |

## Building the Image Locally (Maintainers)

The devcontainer uses a pre-built image from Docker Hub (`jpoley/daax-agents:latest`), based on `node:22-bookworm-slim`. The `lean/Dockerfile` variant uses [Docker Hardened Images (DHI)](https://docs.docker.com/dhi/) for reduced CVE exposure.

To rebuild the image locally:

1. **Build the base image** (required first):
   ```bash
   cd daax-devtools/devcontainer
   docker build -f Dockerfile.base -t jpoley/daax-agents-base:local .
   ```

2. **Build the tools image**:
   ```bash
   docker build --build-arg BASE_IMAGE=jpoley/daax-agents-base:local -t jpoley/daax-agents:local .
   ```

3. **Test with local build** (temporary):
   ```json
   // In devcontainer.json, change:
   "image": "jpoley/daax-agents:local"
   ```

**Note for lean variant**: The lean image (`lean/Dockerfile`) uses DHI which requires authentication. Run `docker login dhi.io` with your Docker Hub credentials first.

## CI/CD Integration

GitHub Actions can use the same container environment:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      # Use the same devcontainer image for CI consistency
      image: jpoley/daax-agents:latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup
        run: |
          # uv is pre-installed in the devcontainer image
          uv sync
      - name: Test
        run: uv run pytest tests/
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    VS Code + Docker                          │
│                    (Host Machine)                            │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Devcontainer                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Base: node:22-bookworm-slim (Debian-based)              ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Python 3.x   │  │ Node.js 22   │  │ GitHub CLI   │      │
│  │ + uv         │  │ + pnpm       │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                 AI Coding Assistants                     ││
│  │  claude  copilot  kiro  codex  gemini                   ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                 Development Tools                        ││
│  │  flowspec  backlog  ruff  pytest  git  gh               ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                 Volume Mounts                            ││
│  │  ./backlog/  ~/.gitconfig  ~/.ssh/  ~/.claude/          ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Three-Phase Build Architecture

The devcontainer uses a **3-phase build architecture** for efficient updates:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Node.js Base Image                                    │
│                       (node:22-bookworm-slim)                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│               BASE Layer (daax-agents-base:latest)                          │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ • Python 3.x + uv package manager                                      │ │
│  │ • Node.js 22 + pnpm                                                    │ │
│  │ • GitHub CLI (gh)                                                      │ │
│  │ • oh-my-posh prompt                                                    │ │
│  │ • Developer tools (tmux, btop, fzf, neovim, asciinema)                │ │
│  │ • Python dev tools (ruff, pytest, claude-code-transcripts)            │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│  Rebuild: Monthly (or when Dockerfile.base changes)                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│               TOOLS Layer (daax-agents:latest)                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ • Claude Code CLI (@anthropic-ai/claude-code)                          │ │
│  │ • GitHub Copilot CLI (@github/copilot)                                 │ │
│  │ • Kiro CLI (optional - via curl installer with checksum)               │ │
│  │ • Get Shit Done (get-shit-done-cc - meta-prompting for Claude)         │ │
│  │ • OpenAI Codex CLI (@openai/codex)                                     │ │
│  │ • Google Gemini CLI (@google/gemini-cli)                               │ │
│  │ • OpenCode CLI (opencode-ai)                                           │ │
│  │ • Agent Browser + MCP Inspector                                        │ │
│  │ • backlog.md + openspec                                                │ │
│  │ • flowspec CLI                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│  Rebuild: Weekly (or when Dockerfile changes)                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│            DEVCONTAINER Layer (daax-devcontainer:latest)                    │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ • Everything from TOOLS layer                                          │ │
│  │ • Devcontainer features pre-baked (zsh, oh-my-zsh, vscode user)       │ │
│  │ • Faster startup (no feature application at runtime)                   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│  Rebuild: Manually, after every tools layer build (no CI)                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why Three Phases?

| Aspect | Single Image | Three-Phase |
|--------|--------------|-------------|
| **Build Time** | ~13 min every time | ~5 min (tools only) |
| **Startup Time** | ~2-3 min (features applied) | ~10-20 sec (prebuilt) |
| **Cache Hit** | Poor (any change rebuilds all) | Excellent (layers cached) |
| **Update Frequency** | Must rebuild everything | Update layers independently |
| **CI Minutes** | High | Low |

### Build Commands

```bash
# Quick build (tools layer only, uses cached base)
./build-push-docker.sh

# Full rebuild (base + tools)
./build-push-docker.sh --base

# Build base layer only
./build-push-docker.sh --base-only

# With version tag
./build-push-docker.sh --base v1.2.3
```

## Build & Publish (Manual)

There is no CI in this repo — no `.github/workflows/` directory and no scheduled rebuilds. Images are built and pushed manually. Paths below are relative to the repo root:

- Tools + base layers: `cd devcontainer && ./build-push-docker.sh` (2-phase: base then tools).
- Single local image: `./rebuild.sh`.
- Push to Docker Hub: `./push.sh`.

Suggested cadence (manual): rebuild the base layer ~monthly to refresh system packages, and the tools layer ~weekly to pick up the latest AI CLIs.

### Monitoring Updates

Check Docker Hub for the latest image:
```bash
docker pull jpoley/daax-agents:latest
docker inspect jpoley/daax-agents:latest | jq '.[0].Created'
```

## References

- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Devcontainer Features](https://containers.dev/features)
- [uv Documentation](https://docs.astral.sh/uv/)
- [CLAUDE.md](../CLAUDE.md) - Development standards
