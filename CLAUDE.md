# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Daax-DevTools** provides container and deployment tooling for the Daax platform. This module contains Dockerfiles, devcontainer configurations, deployment scripts, and docker-compose orchestration for building and running Daax components.

## Purpose

- Build and package Daax components as container images
- Provide devcontainer configurations for development environments
- Deployment scripts for production and staging environments
- docker-compose orchestration for multi-container setups

## Directory Structure

```
daax-devtools/
├── devcontainer/          # Devcontainer configurations and Dockerfiles
│   ├── lean/              # Minimal Alpine-based devcontainer
│   ├── starter-app/       # Starter template devcontainer
│   ├── Dockerfile.base    # Foundation layer (Python, Node, dev tools)
│   ├── Dockerfile.core    # Base + AI CLIs
│   ├── Dockerfile         # Full-featured default image
│   ├── Dockerfile.*       # Specialized variants (flowspec, gsd, openspec)
│   ├── build-all.sh       # Build all Dockerfile variants
│   ├── build-push-docker.sh # Build and push to registry
│   └── README.md          # Full devcontainer documentation
├── scripts/               # Utility scripts
│   └── contain-claude.sh  # Helper for running Claude in container
├── push.sh                # Container image push script
├── rebuild.sh             # Rebuild containers script
├── restart.sh             # Restart services script
├── package.json           # Package configuration
└── README.md              # Module documentation
```

## Commands

```bash
# Rebuild containers
./rebuild.sh

# Push to registry
./push.sh

# Restart services
./restart.sh

# Build devcontainer images (from devcontainer/ directory)
cd devcontainer
./build-push-docker.sh        # Build and push tools layer
./build-push-docker.sh --base # Full rebuild including base layer
./build-all.sh                # Build all Dockerfile variants
```

## Devcontainer Variants

### Default (daax-agents)
Full-featured development environment with all tools:
- Base: node:22-bookworm-slim
- All AI CLIs (Claude, Copilot, Codex, Gemini, Kiro)
- Flowspec, Backlog.md, GSD
- Use case: Full development workflow

### Lean (Fast Startup)
Minimal Alpine-based container (~600MB):
- Base: Docker Hardened Image (Alpine)
- Claude Code + Flowspec + Backlog.md
- Use case: Quick iterations, reduced CVE surface

### Starter App
Template devcontainer for new projects:
- Minimal configuration
- Use case: Starting point for project-specific customization

See [devcontainer/README.md](devcontainer/README.md) for complete image hierarchy and build documentation.

## Key Files

| File | Purpose |
|------|---------|
| `rebuild.sh` | Rebuild and restart containers |
| `push.sh` | Push images to container registry |
| `restart.sh` | Restart running services |
| `devcontainer/build-push-docker.sh` | Build and push devcontainer images |
| `devcontainer/build-all.sh` | Build all Dockerfile variants |

## Integration Points

- **daax-web**: Containerized web workbench deployment
- **Docker/Podman**: Container runtime interface
- **Tailscale**: Network deployment target
- **Container registries**: Image distribution

## Development Workflow

1. Modify Dockerfile or devcontainer config
2. Test locally with `docker build`
3. Push with `./push.sh`

## Notes

- All scripts are executable (`chmod +x`)
- Keep devcontainer configs in sync with daax-cli requirements
- For docker-compose usage, see the main daax-web project

<!-- BACKLOG.MD MCP GUIDELINES START -->

<CRITICAL_INSTRUCTION>

## BACKLOG WORKFLOW INSTRUCTIONS

This project uses Backlog.md MCP for all task and project management activities.

**CRITICAL GUIDANCE**

- If your client supports MCP resources, read `backlog://workflow/overview` to understand when and how to use Backlog for this project.
- If your client only supports tools or the above request fails, call `backlog.get_workflow_overview()` tool to load the tool-oriented overview.

</CRITICAL_INSTRUCTION>

<!-- BACKLOG.MD MCP GUIDELINES END -->
