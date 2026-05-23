# Source Control

---

## Repository
- Host: GitHub — `github.com/daax-dev/daax-devtools`
- Default branch: `main`
- All work lands via PR. No direct commits to `main`.

---

## Branch Naming
- Feature: `feature/<short-topic>`
- Bug fix: `fix/<short-topic>`
- Docs: `docs/<short-topic>`
- Chore / tooling: `chore/<short-topic>`
- Claude Code sessions: harness-assigned name (e.g., `claude/<task>-<id>`). Do not rename mid-session.
- Lowercase, hyphen-separated. Keep names short.

---

## Commits
- Imperative mood, present tense: "add X", not "added X" or "adds X".
- Subject line ≤ 72 characters.
- Body explains the **why**. The diff shows the what.
- One logical change per commit. Mixed-purpose commits get rejected at review.
- Do not amend a commit that has already been pushed unless explicitly asked.

---

## Pull Requests
- Open a PR as soon as the branch has a meaningful commit. Draft is fine.
- PR title = leading commit subject line.
- PR body must include:
  - Problem statement.
  - Approach taken and alternatives considered.
  - Validation evidence (commands run + output: `shellcheck` and/or `docker build`).
  - Which model produced and which model validated (if AI-assisted).
- Never merge your own PR unless explicitly authorized by the operator.
- Squash-merge by default unless the branch history is intentionally curated.

---

## Worktrees
- Long-running parallel work uses `git worktree` rather than branch-switching in place (this keeps a dirty working tree on a feature branch untouched).
- Worktree paths live outside the primary checkout (e.g., `/tmp/<repo>-<branch>` or `../<repo>-<branch>`).
- Worktrees are disposable. Clean them up (`git worktree remove`) when the branch lands.

---

## What Never Gets Committed
- Secrets, tokens, keys, connection strings (`GITHUB_DAAX`, Docker Hub credentials).
- `.env` files with live values.
- Built image artifacts / build cache.
- IDE / OS noise (`.DS_Store`, `Thumbs.db`) — add to `.gitignore`.

---

## Destructive Operations
- Force-push to a shared branch requires explicit operator authorization.
- `git reset --hard`, branch deletion, and history rewrites require confirmation when recovery is uncertain.
- Treat destructive git operations as high-risk: pause, verify the target, get confirmation.

---

## Tags and Releases
- Image version tags follow semver `vX.Y.Z` (optionally `-suffix`, e.g. `v1.2.3-rc1`), validated by `devcontainer/build-push-docker.sh` and published alongside `:latest` to Docker Hub.
- Git tagging / GitHub release notes: [FILL IN — no release automation present in the repo; confirm whether git tags or GitHub Releases are used, separate from image tags].
