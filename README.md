# Daax DevTools

Container, deployment, and infrastructure tooling for Daax.

## Contents

- `devcontainer/` - VS Code devcontainer configurations, Dockerfiles, and build scripts (see [devcontainer/README.md](devcontainer/README.md) for full documentation)
- `scripts/` - Utility scripts (e.g., `contain-claude.sh`)
- `rebuild.sh`, `push.sh`, `restart.sh` - Container management scripts

## Quick Start

### Building and Running Containers

```bash
# Rebuild the container locally
./rebuild.sh

# Build and push to Docker Hub (jpoley/daax-agents)
./push.sh

# Restart the container
./restart.sh
```

For docker-compose usage, see the main [daax-web](../daax-web/) project which contains the `docker-compose.yml`.

### Environment Variables

Set these in your shell or `.env` file:

| Variable | Default | Description |
|----------|---------|-------------|
| `DAAX_WORKSPACE` | `~/prj` | Host path to mount as workspace |
| `TERMINAL_WS_URL` | `ws://localhost:4201` | WebSocket URL for terminal |
| `GITHUB_DAAX` | - | GitHub token for pushing devcontainers |

## Scripts

| Script | Purpose |
|--------|---------|
| `rebuild.sh` | Rebuild and restart the container |
| `push.sh` | Build and push `jpoley/daax-agents` to Docker Hub |
| `restart.sh` | Restart the container |
| `scripts/contain-claude.sh` | Helper for running Claude in container |

## Devcontainers

The `devcontainer/` directory contains VS Code devcontainer configurations and multiple Dockerfile variants:

### Devcontainer Variants
- `devcontainer/lean/` - Minimal Alpine-based container (~600MB) for fast startup
- `devcontainer/starter-app/` - Starter template devcontainer

### Dockerfile Hierarchy
- `Dockerfile.base` - Foundation layer with Python, Node, dev tools
- `Dockerfile.core` - Base + AI CLIs (Claude, Copilot, Codex, etc.)
- `Dockerfile` - Full-featured default image with all tools
- `Dockerfile.flowspec`, `Dockerfile.gsd`, `Dockerfile.openspec` - Specialized variants

See [devcontainer/README.md](devcontainer/README.md) for complete documentation on image variants, authentication, and build commands.
