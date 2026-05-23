# Architecture

Architectural decisions require operator approval before implementation.
ADRs log to `.logs/decisions/architecture.jsonl` (see `.claude/history.md`).

This is a container-image / devcontainer tooling repo, not a running service. Service-oriented concerns (API style, idempotency, cross-service calls, shared databases) do not apply. The patterns below govern the image build system.

---

## Image Layering (the core pattern)
- **2-phase build:** a stable BASE layer (`daax-agents-base`: Python, Node, Go, dev tools, oh-my-posh — changes ~monthly) and a frequently-changing TOOLS layer (`daax-agents`: AI CLIs — changes ~weekly) built on top of it.
- Rationale: AI CLIs update weekly; system deps rarely. Splitting layers keeps the cached base reusable and tools rebuilds fast. Do not collapse the layers without a logged decision.
- Specialized variants (`core`, `flowspec`, `gsd`, `openspec`, `code-server`) and the `lean`/`starter-app` devcontainers branch from this hierarchy. Keep them consistent with the base where they share tooling.

## Build & Publish Rules
- Multi-arch (`linux/amd64,linux/arm64`) via Docker Buildx with a named builder.
- Registry: Docker Hub. Build cache pushed to `:buildcache` tags to speed CI-less rebuilds.
- Version tags must match `vX.Y.Z[-suffix]` (enforced in `build-push-docker.sh`); `:latest` always published.
- Pin tool versions in Dockerfiles; record them in the VERSION TRACKING comment block.

## Configuration & Secrets
- Runtime config via env vars (`DAAX_WORKSPACE`, `TERMINAL_WS_URL`, `TARGETARCH`).
- Secrets (`GITHUB_DAAX`, Docker Hub creds) come from the environment / `docker login` — never in source control or committed env files.

## Anti-Patterns (refuse these)
- Collapsing the base/tools split, or duplicating base-layer deps into the tools layer.
- Unpinned tool versions, or bumping a version without updating the VERSION TRACKING block.
- Single-arch images where multi-arch is expected.
- Secrets baked into image layers or committed to the repo.
- "Temporary" workarounds in build scripts without an expiry date and an owner.

---

## Decision Logging
Log to `.logs/decisions/architecture.jsonl`:
```json
{"id":"arch-001","date":"YYYY-MM-DD","decision":"...","rationale":"...","alternatives":"...","references":["https://..."]}
```

## Reference Architectures
When citing patterns, prefer primary sources:
- Official Docker / Docker Buildx and devcontainer (`containers.dev`) documentation.
- OWASP / CIS Docker Benchmark for container security patterns.
Cite the exact URL in `.logs/references/architecture.jsonl`.
