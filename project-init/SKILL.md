---
name: project-init
version: 1.0.0
description: |
  Bootstrap a project for autonomous Claude Code work: detect the stack, interview
  the gaps, set up scoped least-privilege credentials, generate .claude/project.json
  + permissions, init the Obsidian vault and GitNexus index, write CLAUDE.local.md,
  and verify runbooks by actually executing them. Re-running on an already-configured
  project produces a drift report instead. Everything generated stays local-only
  (never committed to the team repo).
  Use when asked to "set up this project", "bootstrap this project", "project init",
  or "/project-init". Optional args: --phase <name> (resume a phase), --skip <integration>.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

Base directory for this skill: resolve the symlink target of `~/.claude/skills/project-init` (scripts and templates live there; referred to below as `$SKILL`).

## Arguments

- `--phase <detect|interview|credentials|generate|vault|index|memory|runbooks>` — jump to a phase (state from earlier phases is read from `.claude/project-init.state.json`).
- `--skip <tracker|db|cloud|vault|index|runbooks>` — skip an integration/phase entirely (recorded in state so drift mode doesn't nag).

## State

Progress persists in `<root>/.claude/project-init.state.json`: `{"completedPhases": [...], "skipped": [...], "answers": {...}}`. Update it after each phase so any phase is resumable. All facts gathered go here until Phase 4 renders the final `project.json`.

## Phase 0 — Preflight

1. `ROOT=$(pwd)` (run from the project root). If `<root>/.claude/project.json` already exists → **switch to drift mode**: read `$SKILL/references/drift.md` and follow it instead of the phases below.
2. **Prerequisite check**: `bash $SKILL/scripts/check-prereqs.sh` (read-only; one line per dependency: `STATUS|name|scope|found|install_hint`). Handle results by scope:
   - `required` missing (git, python3) → stop and show the install hint; nothing works without these.
   - Integration-scoped (`tracker-*`, `db-*`) → only matters if that integration gets enabled (detection/interview). When it does and the CLI is missing, ask the user (AskUserQuestion): **Install now** (show the hint, wait, re-check) / **Proceed without** (skip that integration; record in state `skipped` so drift mode doesn't nag) / **Abort**.
   - `optional` missing → never block; state the degraded mode and continue:
     | Missing | Degraded behavior |
     |---|---|
     | node/npx | skip Phase 6 (no GitNexus index; code intelligence reduced); npm-based commands can't be verified |
     | obsidian-app | vault works as plain markdown on disk; user can open it in Obsidian later |
     | obsidian-claude-kb repo | Phase 5 scaffolds a minimal vault inline (see Phase 5 fallback) |
     | kb-scripts | runbook notes are written directly into the vault path with the Write tool |
   Offer "install now" with the hint for optional deps too — but default is proceed.
   **Never install anything yourself** — show the command/link and let the user run it (`!` prefix works in-session).
3. `mkdir -p .claude/secrets && chmod 700 .claude/secrets`
4. `bash $SKILL/scripts/exclude-local.sh "$ROOT"` — keeps all generated files out of the team repo via `.git/info/exclude`. If not a git repo it warns and continues.

## Phase 1 — Detect

```bash
bash $SKILL/scripts/detect-stack.sh "$ROOT" > /tmp/detection.json
```

Present the result to the user as a table: tracker, sub-repos (workspace layouts), languages, package managers, command candidates, database, cloud, CI. Read `$SKILL/references/detection.md` if any signal needs interpretation. Save detection JSON into state.

**Workspace layouts** (root is not a git repo but subdirectories are): note each sub-repo; `project.json` lives at the workspace root and `stack.subprojects` lists them. Skills check one directory above their git root for the config, so this works transparently.

## Phase 2 — Interview gaps

Ask (AskUserQuestion, batched, max 4 per call) ONLY for what detection could not establish:

- One-line project description.
- Vault name (default: project dir basename).
- Target branch for MRs/PRs (default: detected default branch).
- Tracker specifics if a tracker was detected: ticket project path (may differ from the code repo), board ID, iteration cadence ID, status labels. Offer "skip tracker board" — `/ship-it` and `/review-pr` still work with just the repo.
- Database name(s) and whether a DB integration is wanted at all.
- Cloud profile/regions if cloud was detected.
- Staging/dev environment URLs + healthcheck paths.
- Confirm autonomy tier `standard` (dev-loop writes autonomous; merge/deploy/db-write/cloud-mutation/ticket-state-change blocked).

Record every user-provided value with `"source": "user"` — drift mode must never silently overwrite these.

## Phase 3 — Scoped credentials (per integration; each skippable)

Read `$SKILL/references/credentials.md` and follow the recipe for each enabled integration. The pattern for every one:

1. Print the exact least-privilege recipe (SQL / token settings / IAM policy) for the USER to execute — creating credentials requires their privileged access; never ask them to paste admin passwords to you.
2. Receive only the resulting scoped credential (or its file location).
3. Write it to `.claude/secrets/<file>` with `chmod 600`.
4. **Verify immediately with one harmless read** (`SELECT 1`, `glab auth status` / one GET, `aws sts get-caller-identity`). Do not record an unverified credential.

## Phase 4 — Generate config + permissions

1. Render `$SKILL/templates/project.json.template` with everything from state → `<root>/.claude/project.json`. Fill `detection.fingerprints` from `/tmp/detection.json`. Set real values for `commands` from the chosen candidates (still `verified: null` until Phase 8).
2. Compose `<root>/.claude/settings.local.json` permissions from `$SKILL/templates/permissions/` fragments per `$SKILL/references/permissions.md`: always `base.json` + `git.json`; add `tracker-<type>.json`, `db-<engine>.json`, `cloud-<provider>.json` for enabled integrations. Substitute `{{placeholders}}` with concrete values; expand per-protected-branch and per-prefix rules; drop allow entries whose command is null. Strip `_comment` keys. If a `settings.local.json` already exists, merge: show the user any existing rules not in the generated set and ask which to keep.
3. Merge `$SKILL/templates/hooks.json` into the `hooks` section of the same `settings.local.json` (strip `_comment`). This wires the /work-ticket ship gate (`$SKILL/scripts/ship-gate.py`): MR/PR creation on a branch with an active task in `.claude/tasks/` is blocked until that task's spec is approved and tests pass. If a `PreToolUse` entry with the same command already exists, leave it as is.
4. Ensure project MCP config (`<root>/.mcp.json`) has the obsidian filesystem server for the project vault if the global one doesn't cover it (vault path = `~/ObsidianVaults/<vault>`).

## Phase 5 — Vault init

If `~/ObsidianVaults/<vault>` does not exist and obsidian-claude-kb is installed (prereq check passed): run the `/kb-init` command it installed (`~/.claude/commands/kb-init.md`) with the vault name — that is the stable interface regardless of where the repo was cloned. Never reference a clone path directly.

**Fallback** (obsidian-claude-kb not installed): scaffold a minimal vault inline:

```bash
V=~/ObsidianVaults/<vault>
mkdir -p "$V"/{architecture,context,decisions,domain,explorations,integrations,runbooks,sessions,tools}
```

plus a one-paragraph `_index.md` naming the project and the category folders. Same conventions, no templates — fully usable by kb-save/kb-search and plain file tools.

If the Obsidian app is installed, remind the user of the one manual step: open the folder as a vault in Obsidian once. If it isn't, note the vault works as plain markdown and they can adopt it into Obsidian later (https://obsidian.md/download).

## Phase 6 — GitNexus index

Skip this phase (with a note in the report) if node/npx is missing per the prereq check — everything else still works, you just lose graph-based code intelligence.

Check `~/.gitnexus/registry.json` for each path in `gitnexus.indexedPaths` (for workspaces, ask which sub-repos are worth indexing — default: the main code repos, not infra/scratch). For unindexed paths:

```bash
cd <path> && npx gitnexus analyze
```

This can take minutes on large repos — tell the user before starting.

**Side-effect cleanup** (gitnexus analyze writes into the repo): it appends `.gitnexus` to the project's `.gitignore` and creates/updates `CLAUDE.md` + `AGENTS.md` with its instruction block. After indexing: revert the `.gitignore` change (`git checkout -- .gitignore` if that was the only modification — check the diff first). The generated `CLAUDE.md`/`AGENTS.md` stay but are kept local by the exclude entries (note: `.git/info/exclude` only affects untracked files, so a project's already-committed CLAUDE.md is unaffected).

## Phase 7 — Project memory → CLAUDE.local.md

Generate `<root>/CLAUDE.local.md` from `$SKILL/templates/CLAUDE.local.md.template`. Fill it by actually studying the codebase (GitNexus queries, directory survey, recent commit conventions) — not just the interview. Keep it under ~150 lines; it loads every session. Include the self-heal contract verbatim from the template.

## Phase 8 — Verified runbooks

Read `$SKILL/references/runbooks.md` for the format and verification protocol. For each non-null command in `project.json` `commands` (order: install → lint → test → build → dev):

1. Execute it (dev server: launch in background, poll `readyCheck` up to 60s, then kill).
2. Success → set `verified: <today>` + `source: "verified"` in `project.json`; write/update the runbook note in the vault via `bash ~/.claude/scripts/kb-save.sh` (kb-scripts missing → write the note file directly into `<vaultPath>/runbooks/` with the Write tool, same frontmatter format).
3. Failure → try to fix (max ~3 attempts); record every failure + the fix that worked in the runbook's Troubleshooting section. Unresolvable → leave `verified: null`, mark runbook `status: broken`, tell the user.

This phase is the longest; it is resumable per command (`--phase runbooks` continues with unverified commands only).

## Phase 9 — Report

Summary table: integration | status (configured/skipped/failed) | where it lives. List residual manual steps (e.g. "open vault in Obsidian", unverified commands). Confirm what is now possible autonomously and what stays blocked.

## Drift mode (Phase D)

Triggered by Phase 0 when `project.json` exists. Follow `$SKILL/references/drift.md`.

## Hard rules

- Never write a secret into `project.json`, `settings.local.json`, `CLAUDE.local.md`, a runbook, or any output shown in chat.
- Never commit anything in the target project; never touch its `.gitignore` (use `.git/info/exclude`).
- Never request the user's admin/owner credentials — recipes are for them to run.
- Generated permission rules must express the standard autonomy boundary; loosening it requires the user's explicit per-field confirmation.
