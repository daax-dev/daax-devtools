# Workflow

## Planning
- A plan is required for any non-trivial change.
- Trivial: typo fix, single-line config update, obvious rename. Everything else requires a plan.
- Write the plan down — in the PR description, the Backlog.md task, or `.logs/decisions/`. Plans held only in chat do not count.
- Present trade-offs as facts: option, cost, risk, reversibility. The operator decides; the agent executes.
- Do not start coding until the plan is approved.

---

## Execution Discipline
- State assumptions that affect implementation. If the request has multiple plausible readings, ask before editing.
- Smallest change that satisfies the verified goal. No speculative features, abstractions, or config.
- Touch only what the task requires. No adjacent cleanup or drive-by refactors. Every changed line traces to the request or its validation.
- Remove only the orphans your change created; leave pre-existing dead code (mention it, don't delete).
- Define a verifiable goal before coding. When changing a script or Dockerfile, validate by running it / building the image.

---

## Work Intake
Tasks originate from (check in this order):
1. Backlog.md (`backlog/` config; system of record). Read `backlog://workflow/overview` via MCP, or call `backlog.get_workflow_overview()`.
2. Direct request from operator.

Identify the source before starting. If the same task appears in multiple systems, ask which is canonical.

---

## Model Selection
- Match model capability to task complexity. Do not waste large models on small tasks.
- Code with one model; validate with a model from a **different provider where possible** (e.g., produced by Claude/Anthropic, validated by Codex/OpenAI, or vice versa). Prefer cross-provider; a different model from the same provider is the fallback; same model is last resort. Record both — producer and validator — in the PR description, and note if cross-provider was not possible.
- Call out when a task requires a paid API call. State the cost estimate before incurring it.

---

## Communication
- Report blockers immediately. No silent workarounds.
- Surface uncertainty. State confidence level. No claims of certainty without a validated primary source.
- Objective language. No first-person pronouns. No apologies.

---

## Definition of Done
This repo has **no automated test suite**. Validation = static lint of shell + a real container build. A task is done only when:
- [ ] Changed shell scripts pass `shellcheck *.sh devcontainer/*.sh scripts/*.sh` (shellcheck is not vendored in the repo — install it, e.g. `apt-get install shellcheck` / `brew install shellcheck`). If shellcheck is genuinely unavailable, run `bash -n <script>` as a syntax-only fallback and state that explicitly.
- [ ] Changed Dockerfiles build successfully — e.g. `docker build -f devcontainer/Dockerfile devcontainer` for the tools layer, or the relevant variant. The build succeeding is the verification.
- [ ] PR opened with problem statement, approach, and validation evidence (commands run + output).
- [ ] Non-trivial decisions logged in `.logs/decisions/` per `.claude/history.md`.
- [ ] Validation pass by a separate model — cross-provider (Claude ↔ Codex) where possible — recorded in the PR description as `Validation:` producer model + validator model + verdict (note if cross-provider was not possible).
- [ ] Backlog.md task updated to Done with a link to the PR/commit.
