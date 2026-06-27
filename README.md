# Daax DevTools

Container, deployment, and infrastructure tooling for Daax.

## Contents

- `devcontainer/` - VS Code devcontainer configurations, Dockerfiles, and build scripts (see [devcontainer/README.md](devcontainer/README.md) for full documentation)
- `src/generate-tests/` - Testcontainers code generator (`daax dev generate-tests`)
- `scripts/` - Utility scripts (e.g., `contain-claude.sh`)
- `rebuild.sh`, `push.sh`, `restart.sh` - Container management scripts

## Generate Testcontainers setup from devcontainer services

When a devcontainer declares backing services (postgres, redis, …) via a
`dockerComposeFile`, you can auto-generate idiomatic Testcontainers bootstrap
code for Go and TypeScript instead of hand-writing it:

```bash
# Emit Go + TS Testcontainers setup into ./testcontainers
bun run generate-tests --devcontainer .devcontainer/devcontainer.json

# Preview without writing any files
bun run generate-tests --devcontainer .devcontainer/devcontainer.json --dry-run

# One language only, custom output dir
bun run generate-tests --lang go --out internal/testsupport
```

- **Go** uses `testcontainers-go` `GenericContainer` for every service and
  assembles a connection string from `Host()` + `MappedPort()`; containers are
  shared per suite via `TestMain`.
- **TypeScript** uses first-class modules (`PostgreSqlContainer`,
  `RedisContainer`, `ElasticsearchContainer`) with a `GenericContainer`
  fallback; the sample Vitest suite shares containers via `beforeAll`/`afterAll`.
- `depends_on` is honored: dependencies are started before their dependents.

Run `bun run generate-tests --help` for all flags. Tests: `bun test tests/`
(fast, Docker-free) and `bun run test:integration` (real compile + live
container starts).

## Quick Start

### Building and Running Containers

```bash
# Rebuild the container locally
./rebuild.sh

# Build and push to GitHub Container Registry
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
| `push.sh` | Build and push to GitHub Container Registry |
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
