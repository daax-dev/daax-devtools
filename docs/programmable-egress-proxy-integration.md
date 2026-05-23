# daax-devtools Integration: Programmable Egress Proxy (cooperative mode, Phase 2)

**Status**: Design — Phase 2, not yet implemented
**Canonical PRD**: `daax-dev/dx` → `arch/prd/programmable-egress-proxy.md` (v1.3.0)
**Tracking issue**: [daax-dev/dx#55](https://github.com/daax-dev/dx/issues/55)

> This doc is the **daax-devtools-specific** slice of the cross-cutting PRD. devtools is a
> **Phase 2** target and a deliberately weaker (cooperative) enforcement mode. Read the canonical
> PRD — especially the **Enforcement Asymmetry** section — before this one.

---

## ⚠ Read this first: cooperative ≠ forced

The devtools container shares a kernel with the host and may have broad network capability. Egress
is *steered* through the proxy via `HTTPS_PROXY`/`HTTP_PROXY` env vars plus docker network rules.
**A process that ignores those env vars, or that has `CAP_NET_RAW`/root and opens a raw socket,
can bypass the proxy entirely.**

Therefore, in devtools the egress proxy provides **convenience secret-brokering for well-behaved
tooling** — it is **not** a sandbox for hostile code and does **not** carry the secret-isolation
guarantee that nanofuse forced mode does. Any UX or doc must say "egress is *steered*, not
*enforced*" for this target. Workloads that need a hard boundary belong in nanofuse.

This is why devtools is sequenced **after** the nanofuse v1: ship the model where the guarantee
holds, then reuse the shared engine here for convenience with honest framing.

---

## What lands in daax-devtools

The proxy data plane / policy engine / secret store / audit schema come from the **shared Go
library** built in the nanofuse v1. devtools owns only the **cooperative adapter**:

| Area | devtools-specific responsibility | Touches |
|------|----------------------------------|---------|
| Proxy placement | Run the egress proxy as a **sidecar** (separate container or host process) on the docker network the devtools container attaches to | `docker-compose.yml` (in daax-web), devcontainer network config |
| Steering | Set `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` container-wide; **sanitize `NO_PROXY`** so it cannot be set to `*` to disable steering | `devcontainer/devcontainer.json`, `devcontainer/postCreate.sh` |
| CA trust | Add the per-run CA **public** cert to the container CA bundle at build/postCreate time; document Docker/BuildKit explicit-trust needs | `devcontainer/Dockerfile*`, `postCreate.sh` |
| Hardening (best-effort) | Drop `CAP_NET_RAW`, forbid host network mode, restrict Docker socket exposure, add per-container netns nftables rules where the runtime allows | container run config |
| Client identity | Source-bound bearer token injected by the launcher (not via shell history), bound to container netns + sandbox-id, short TTL, audience-scoped, revocable | launcher / postCreate |
| Audit | Emit audit events with `enforcement: "cooperative"` so logs never imply a hard boundary | shared audit lib |

---

## Honest acceptance criteria

- [ ] A well-behaved tool (`curl` honoring `HTTPS_PROXY`) reaches an allowlisted upstream with the
      secret injected host-side and no secret in the container env.
- [ ] `NO_PROXY=*` set inside the container → sanitized / ineffective.
- [ ] **Bypass is demonstrated and documented**: a test shows that a raw socket / `CAP_NET_RAW`
      process can egress outside the proxy, and the docs + UX label this limitation explicitly.
- [ ] Audit events for this target carry `enforcement: "cooperative"`.

---

## Dependencies / sequencing

- **Depends on the nanofuse v1** shipping the shared library (policy engine, proxy data plane,
  secret store, audit schema, per-run CA).
- Then this adapter wires the sidecar + steering + CA trust + cap hardening into the devcontainer.

## Out of scope here

Everything in the canonical PRD's forced-mode guarantee. devtools never claims it.
