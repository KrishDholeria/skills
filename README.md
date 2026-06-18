# skills

Reusable Claude Code setup. Each top-level directory containing a `SKILL.md` is a global Claude Code skill; `install.sh` symlinks them into `~/.claude/skills/` so this repo is the single source of truth — edit here, every project picks it up immediately.

## Quickstart

```bash
git clone https://github.com/KrishDholeria/skills.git
cd skills && ./install.sh          # symlinks the skills into ~/.claude/skills/
```

Then, from inside any project you work on:

```
/project-init        # interviews you, detects the stack, wires the project up
```

That's it. Works with just `git` + `python3` — everything else is optional and degrades gracefully (see [What works with zero optional tools](#what-works-with-zero-optional-tools)).

## What's inside

| Skill | Purpose |
|---|---|
| `project-init` | Bootstrap a project for Claude Code: detect the stack, interview gaps, set up scoped credentials, generate config/permissions, init the Obsidian vault + GitNexus index, write `CLAUDE.local.md`, and verify runbooks by executing them. Re-run on a configured project to get a drift report. |
| `work-ticket` | **Orchestrator** that drives a ticket (or an ad-hoc free-text task) end-to-end by sequencing the suite below: `understand-task` → `grill-me` (interview) → `create-spec` → **human approval gate** → `implement` → `ship-it` → learn. Owns the resumable pipeline state in `<root>/.claude/tasks/<id>/state.json` and the approval gate; each stage's real work lives in its own standalone skill. A PreToolUse ship gate (wired per-project by `project-init`) blocks MR creation until the spec is approved and tests pass. |
| `understand-task` | Suite stage 1+2, also standalone. Intake + context: fetch the ticket (or build a brief from a free-text prompt), gather context (KB, code graph, linked docs, web), and write `ticket.md` + `context.md`. **Creates** the task dir the rest of the suite reads from. |
| `create-spec` | Suite stage 3, also standalone. Turn the persisted artifacts (`ticket.md`/`context.md`/`interview.md`) plus current session context into a precise, testable `spec.md`. Locates the task dir via the shared `task-env.sh` helper. |
| `implement` | Suite stage 4, also standalone. Implement an approved `spec.md` test-first via a fresh sonnet subagent, then independently validate the diff against every acceptance criterion (re-running tests/lint) and verify behavior in the running app. Writes `validation.md` + `verify.md`. |
| `ship-it` | Suite stage 5, also standalone. Push branch, generate MR/PR description, create/update draft MR (GitLab) or PR (GitHub). Stack read from `.claude/project.json`. |
| `view-tickets` | Show the current iteration/sprint board, grouped by status. Tracker config from `project.json`. |
| `review-pr` | Review an MR/PR against a quality checklist. |
| `post-review-comments` | Post selected review issues as inline MR/PR comments. |
| `connect-db` | Read-only database access (Postgres/MySQL). No default credentials — uses the scoped read-only user from `project.json`. |
| `fetch-doc` | Read a document URL as plain text. Google Docs/Sheets/Slides → export endpoints; anonymous first, then a one-time exported cookie file (`~/.claude/secrets/google-cookies.txt`) for restricted docs. Used by `work-ticket` to read docs linked from tickets. |

## Prerequisites

`/project-init` checks all of these itself (`project-init/scripts/check-prereqs.sh`) and prompts you to install what's missing — or proceeds in degraded mode where it can. Nothing is ever installed automatically.

### Required

| Tool | Why | Install |
|---|---|---|
| git | repo detection, local-only excludes, all git workflows | `sudo apt install git` |
| python3 | detection/drift scripts, JSON handling | `sudo apt install python3` |
| Claude Code | the thing being configured | https://claude.com/claude-code |

### Per integration (only if the project uses it)

| Tool | Needed for | Install |
|---|---|---|
| glab | GitLab MRs/tickets (`/ship-it`, `/view-tickets`, `/review-pr`) | https://gitlab.com/gitlab-org/cli#installation or `sudo apt install glab` |
| gh | GitHub PRs/issues | https://github.com/cli/cli#installation |
| jira | Jira boards (ankitpokhrel/jira-cli) | https://github.com/ankitpokhrel/jira-cli#installation |
| psql | Postgres read-only access (`/connect-db`) | `sudo apt install postgresql-client` |
| mysql | MySQL read-only access | `sudo apt install mysql-client` |

Missing one of these? The bootstrap offers: install now, or skip that integration (recorded, so re-runs don't nag).

### Optional (graceful degradation without them)

| Tool | Adds | Without it | Install |
|---|---|---|---|
| node + npx | GitNexus code-graph indexing; verifying npm-based commands | indexing phase skipped, reduced code intelligence | https://github.com/nvm-sh/nvm (recommended) |
| GitNexus | code intelligence (impact analysis, flow tracing) | — | auto-fetched by `npx gitnexus` on first use; `npm i -g gitnexus` to pin |
| Obsidian app | nice UI over the knowledge vault | vault still works as plain markdown on disk | https://obsidian.md/download |
| Google cookie export (browser extension, e.g. "Get cookies.txt LOCALLY") | `fetch-doc` reading restricted Google Docs linked from tickets | public/"anyone with link" docs still readable; restricted ones recorded as context gaps | one-time setup in `fetch-doc/SKILL.md` |
| [obsidian-claude-kb](https://github.com/KrishDholeria/obsidian-claude-kb) | vault templates, `/kb-*` commands, session hooks (auto-load/save/search) | minimal vault scaffolded inline; runbook notes written directly to the vault | `git clone https://github.com/KrishDholeria/obsidian-claude-kb.git && bash obsidian-claude-kb/install.sh` — full guide in its README |

## Install

Clone anywhere you like — the installer figures out its own location, so the path doesn't matter:

```bash
git clone https://github.com/KrishDholeria/skills.git
cd skills && ./install.sh
```

Then run `/project-init` inside any project you want Claude Code to work in.

Idempotent — safe to re-run after `git pull` to pick up updates. It symlinks each skill dir into `~/.claude/skills/` (so the repo stays the single source of truth; edits apply immediately), and moves any superseded legacy files into `legacy/` as backups. Symlinks mean updating is just `git pull` — no reinstall needed.

> Want to customize the skills for your own use? Fork the repo first and clone your fork, so your changes have somewhere to live and you can still pull upstream updates.

### What works with zero optional tools

Right after `./install.sh` — with **only `git` + `python3`** installed and no Obsidian, no GitNexus, no tracker/DB CLIs — the full core loop already works. Every optional integration is detected at runtime and degrades cleanly when absent:

- **No Obsidian / KB** → `/project-init` scaffolds a plain-markdown vault on disk and runbook/decision notes are written as ordinary files. Nothing requires the Obsidian app or the [obsidian-claude-kb](https://github.com/KrishDholeria/obsidian-claude-kb) repo.
- **No GitNexus / node** → code-graph indexing is skipped; skills fall back to Grep/Glob exploration.
- **No `glab`/`gh`/`jira`/`psql`/`mysql`** → those integrations are simply offered as skippable; `/project-init` records the skip so re-runs don't nag.

`/project-init` runs `project-init/scripts/check-prereqs.sh` first and tells you exactly what's present, what's missing, and what each missing tool would add — it never installs anything for you.

## Per-project config

Skills read `<project>/.claude/project.json` (generated by `/project-init`, never committed — kept local via `.git/info/exclude`). Secrets live in `<project>/.claude/secrets/` (700/600), referenced by path, never inlined in config or permission rules.

## Design

See `docs/DESIGN.md` for the decision record (least-privilege model, autonomy boundary, drift mode, local-only policy).
