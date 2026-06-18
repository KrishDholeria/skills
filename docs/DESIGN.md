# Reusable Claude Code Project Bootstrap (`/project-init`)

## Context

The goal is a reusable setup so that any project — regardless of stack — can be bootstrapped once, after which Claude Code can handle tasks independently: understand the code, run/test/verify it, read the DB, query the tracker, ship draft MRs/PRs. Today this exists only as a hand-built setup for a single project, with hardcoded stack assumptions and a plaintext database password baked into a project's `.claude/settings.local.json` and a `connect-db` command.

Decisions resolved by interview (fixed — do not relitigate):
- **Deliverable**: a `/project-init` bootstrap skill + templates, developed in this `skills/` repo (the former `claude-setup/` dir, renamed), symlink-installed into `~/.claude/skills/`.
- **Scope**: six access categories, all stack-configurable — code intelligence (GitNexus + project memory), KB (Obsidian vault), tracker (GitLab/GitHub/Jira), DB (Postgres/MySQL, read-only), cloud (AWS/GCP), running environments.
- **Discovery**: auto-detect stack from repo signals; interview only the gaps.
- **Least privilege, two layers**: dedicated scoped credentials (read-only DB role, scoped tracker token, read-only IAM profile) + tool guardrails (deny rules, read-only wrapper skills).
- **Autonomy boundary**: autonomous = edit/test/commit/push feature branches/draft MRs/ticket comments/all reads. Blocked = merge to protected branches, deploys, DB writes, cloud mutations, ticket state changes.
- **Context depth**: generated project memory + GitNexus index + Obsidian vault + runbooks **verified by actually executing the commands**.
- **Skill architecture**: one generic global copy of each task skill, reading per-project `.claude/project.json`.
- **Maintenance**: idempotent re-run with drift report; runbooks self-heal during normal work.
- **Run mode**: interactive-first, headless-ready (no interactive-OAuth-only dependencies in core flows).
- **Config home: everything local-only** — nothing Claude-related committed to team repos; use `CLAUDE.local.md` + `.git/info/exclude`.
- **Validation**: a fresh minimal project first, then migrating an existing real-world project.

Existing assets reused unchanged: `~/.claude/scripts/kb-*.sh` + `load-vault.sh` (already vault-agnostic), `~/Desktop/Projects/obsidian-claude-kb/project-init.sh` (vault scaffolding), `~/.claude/hooks/gitnexus/gitnexus-hook.cjs`, GitNexus CLI v1.5.3.

## Repo layout — `skills/`

The repo is named `skills` and its top-level directories ARE the skills (rename the current `claude-setup/` dir to `skills/` first, preserving `.remember/` and `.claude/`).

```
skills/
├── README.md
├── install.sh                        # idempotent: symlinks each skill dir into ~/.claude/skills/,
│                                     # backs up superseded ~/.claude/commands/*.md + old ship-it to legacy/
├── project-init/
│   ├── SKILL.md                      # bootstrap orchestrator (phases below)
│   ├── scripts/
│   │   ├── detect-stack.sh           # read-only repo scan → detection JSON
│   │   ├── drift-diff.sh             # detection JSON vs project.json → drift table
│   │   └── exclude-local.sh          # marker-guarded append to .git/info/exclude
│   ├── references/                   # detection.md, credentials.md, permissions.md, runbooks.md, drift.md
│   └── templates/                    # consumed only by project-init, so they live inside it
│       ├── project.json.template
│       ├── CLAUDE.local.md.template
│       ├── git-exclude.txt
│       ├── secrets/README.md         # pgpass / my.cnf / env file formats
│       └── permissions/              # composable settings.local.json fragments:
│           base.json, git.json, tracker-{gitlab,github,jira}.json,
│           db-{postgres,mysql}.json, cloud-{aws,gcp}.json
├── ship-it/SKILL.md                  # generic rewrites of the 5 task skills
├── view-tickets/SKILL.md
├── review-pr/SKILL.md
├── post-review-comments/SKILL.md
├── connect-db/SKILL.md
├── legacy/                           # backups of superseded commands/skills (not symlinked)
└── docs/DESIGN.md                    # decision record (not symlinked)
```

`install.sh` symlinks only directories containing a `SKILL.md`; `legacy/` and `docs/` are skipped.

Symlinks (not copies) make this repo the single source of truth — a fix to `skills/ship-it/SKILL.md` propagates to every project instantly. Repo gets its own git history. `install.sh` must move the superseded `~/.claude/commands/{connect-db,view-tickets,review-pr,post-review-comments}.md` to `legacy/` (a same-named command and skill would conflict); `kb-*.md` commands and `~/.claude/scripts/` stay untouched.

## `project.json` schema (lives at `<project>/.claude/project.json`, never committed)

No secrets — only pointers (credential file paths / env var names). Key sections:

- `project`: name, root, description, vault name
- `stack`: languages, runtimes, packageManagers, frameworks, subprojects (monorepo paths)
- `commands`: install/test/lint/build/dev — each `{cmd, cwd, verified: <date|null>, source: detected|user|verified}`; `dev` also has `url` + `readyCheck`
- `git`: defaultBranch, targetBranch, protectedBranches, branchPrefixes, remote
- `tracker`: type (gitlab|github|jira), cli, project, repoProject, boardId, iterationCadenceId, statusLabels, auth method
- `database`: engine, host, port, databases, user (e.g. `claude_ro`), credentialFile (`.claude/secrets/pgpass`), readOnly flags
- `cloud`: provider, profile (e.g. `claude-readonly`), regions
- `environments`: name, url, healthcheck, access
- `autonomy`: tier + blocked list (merge-to-protected, deploy, db-write, cloud-mutation, ticket-state-change)
- `kb`: vaultPath, runbooks category
- `gitnexus`: indexedPaths
- `detection`: fingerprints (sha256 of remotes/lockfiles/docker-compose/CI config) + lastRun — drives drift mode

`source` field rule: drift mode never silently overwrites `source: "user"` values.

Secrets live in `<project>/.claude/secrets/` (dir 700, files 600): `pgpass` (native PGPASSFILE format), `my.cnf`, or `env`. This removes passwords from permission strings entirely.

## Bootstrap skill flow (`/project-init`)

State in `.claude/project-init.state.json`; phases resumable (`--phase X`) and skippable (`--skip cloud`):

- **0 Preflight**: if `project.json` exists → drift mode. Create `.claude/`, `.claude/secrets/`; run `exclude-local.sh` (skip + warn for non-git).
- **1 Detect**: `detect-stack.sh` — git remotes → tracker; lockfiles/manifests → runtimes + candidate commands; docker-compose/.env keys → DB; terraform/SDK deps → cloud; CI config → lint/test. Show detection table.
- **2 Interview gaps**: AskUserQuestion only for undetectable facts (board IDs, target branch, staging URLs, vault name default = dir basename, autonomy confirmation). Integrations individually skippable.
- **3 Scoped credentials** (guided; user executes privileged parts; each cred verified with one harmless read before recording):
  - Postgres: `CREATE ROLE claude_ro LOGIN ... GRANT SELECT` recipe → write `.claude/secrets/pgpass` → verify `SELECT 1`
  - GitLab: project access token, Developer + `api` scope (needed for MR create; residual risk noted, mitigated by deny rules)
  - GitHub: fine-grained PAT (contents:rw, pull-requests:rw, issues:rw)
  - AWS: profile bound to `ReadOnlyAccess`; GCP: `roles/viewer` service account
- **4 Generate config + permissions**: render `project.json`; compose `.claude/settings.local.json` from selected permission fragments with values substituted; write `.mcp.json` obsidian servers if missing.
- **5 Vault init**: reuse `~/Desktop/Projects/obsidian-claude-kb/project-init.sh "<vault>"` (skip if vault exists); remind about manual "open folder as vault" step.
- **6 GitNexus index**: check `~/.gitnexus/registry.json`; `npx gitnexus analyze` per path; monorepos: ask which subpaths.
- **7 Project memory → `CLAUDE.local.md`**: generated from GitNexus map + directory survey + commit conventions + interview. Sections: What this is / Architecture map / Key directories / Conventions / Commands (pointer to project.json) / Gotchas / **Self-heal contract** ("when a documented command fails, fix it, update the runbook note + project.json verified date").
- **8 Verified runbooks**: execute every `commands` entry (dev server in background, poll readyCheck, kill). Success → stamp `verified`, write runbook note to vault `runbooks/` via `kb-save.sh`. Failure → record fix attempts in Troubleshooting; leave `verified: null` and report. Longest phase; resumable per command.
- **9 Report**: configured / skipped / residual manual steps / file locations.

## Permission strategy (autonomy boundary → rules)

**Global deny baseline** (one-time addition to `~/.claude/settings.json` — deny beats allow everywhere): force-push, `glab mr merge*`, `gh pr merge*`, `terraform apply|destroy*`, `kubectl apply|delete*`, `aws * delete|terminate|put|create*`, `gcloud * delete|deploy*`.

**Per-project fragments** → composed into `.claude/settings.local.json`:
- `git.json`: allow add/commit/checkout -b/push feature-prefix globs; deny push to each protected branch
- `tracker-gitlab.json`: allow `glab mr create|update|view|diff|list`, `glab issue list|view|note`, `glab api projects/*`; deny `glab issue close|reopen|update`, `glab mr approve|merge`. (`glab api` mutations can't be fully pattern-blocked — documented residual risk; skill text mandates GET-only.)
- `db-postgres.json`: single allowed shape `Bash(PGPASSFILE=<root>/.claude/secrets/pgpass psql -h <host>*)` — no password in any rule; real enforcement is the `claude_ro` role, skill keyword-check + `BEGIN READ ONLY` is layer 2
- `cloud-aws.json`: allow `describe*|get*|list*|logs|s3 ls|s3 cp s3://* -` under the dedicated profile
- `base.json`: rendered project commands (test/lint/build), staging-URL curls, existing kb/obsidian allows

## Generic skill rewrites (all read project.json from git root; missing file → "run /project-init" + legacy fallback)

| Skill | Change | Fallback |
|---|---|---|
| ship-it | target branch + tracker dispatch (glab vs gh) + prefixes/protected from config | glab + develop (current) |
| view-tickets | board query built from `tracker.project/boardId/iterationCadenceId/statusLabels`; gh/jira variants | error + /project-init hint |
| review-pr | glab/gh dispatch; checklist unchanged | glab |
| post-review-comments | discussions API using `tracker.repoProject` directly (drops brittle search lookup) | current lookup |
| connect-db | **no default creds ever**; engine dispatch; PGPASSFILE/defaults-extra-file; keep keyword check + read-only transaction | ask for connection details; never assume password |

## Local-only mechanics

- Project memory = `CLAUDE.local.md` (auto-loaded Claude Code memory tier, intended to be uncommitted).
- `git-exclude.txt` appended marker-guarded to `.git/info/exclude` (never touches team `.gitignore`): `CLAUDE.local.md`, `.claude/`, `.gitnexus/`, `.mcp.json`.
- Non-git projects: skip exclude with warning; everything else works.

## Verified-runbook format (vault `runbooks/`, via `kb-save.sh`)

Frontmatter: `tags: [runbook, claude-context-conditional]` (kept out of SessionStart auto-load budget — pulled on demand), `status: verified|unverified|broken`, `verified: <date>`, `command`, `cwd`. Body: Purpose / Preconditions / Steps / Expected output (captured snippet) / Troubleshooting (real failures + fixes from the verification run) / Last verified (tool versions).

## Drift mode (re-run on configured project)

1. Re-detect; `drift-diff.sh` vs stored fingerprints.
2. Drift table: field | configured | detected | proposed action.
3. Approval per category; `source: "user"` fields never auto-overwritten.
4. Regenerate `project.json` + affected permission rules; bootstrap owns `settings.local.json` but diffs first and asks before dropping any hand-added rule.
5. Re-verify only commands whose manifests changed; update runbooks; refresh fingerprints.

## Implementation order

| # | Step | Effort |
|---|---|---|
| 1 | Rename repo to `~/Desktop/Projects/skills/`, scaffold layout + README + `install.sh` (symlinks, legacy backups) | 0.5d |
| 2 | `project.json.template` + `detect-stack.sh` + `exclude-local.sh` | 1d |
| 3 | Permission fragments + global deny baseline in `~/.claude/settings.json` | 0.5d |
| 4 | Rewrite 5 generic skills against schema (ship-it first) | 1d |
| 5 | `project-init/SKILL.md` phases 0–4 + references | 1d |
| 6 | Phases 5–8 (vault, GitNexus, CLAUDE.local.md, verified runbooks) | 1d |
| 7 | Drift mode | 0.5d |
| 8 | **Validation A**: `/project-init` on a minimal-stack project (exercises skip paths) | 0.5d |
| 9 | **Validation B**: migrate an existing real-world project | 1d |

## Verification

- **Validation A acceptance**: bootstrap completes on a minimal project; skip paths work (no tracker board, no DB); generated `CLAUDE.local.md`, vault, runbooks exist; runbook commands actually verified.
- **Validation B (real-world migration) acceptance**:
  - `project.json` reproduces the project's board, iteration cadence, and target branch
  - `/view-tickets`, `/ship-it`, `/connect-db`, `/review-pr` work identically via config indirection
  - `claude_ro` Postgres role exists; `.claude/secrets/pgpass` (600) in place
  - All plaintext database passwords gone from the project's `.claude/settings.local.json` and connect-db skill
  - Regenerated `settings.local.json` replaces the prior hand-built allowlist
  - Drift mode on an unchanged project reports "no drift"
- **Guardrail spot-checks**: attempt `git push origin develop`, `glab mr merge`, a DB `UPDATE` via connect-db, `aws s3 rm` — all must be refused (deny rule, skill guardrail, or credential).

## Key files

- `skills/project-init/templates/project.json.template` — the schema everything consumes
- `skills/project-init/SKILL.md` — orchestrator
- `skills/project-init/scripts/detect-stack.sh` — detection engine (bootstrap + drift)
- `skills/install.sh` — symlink installer
- Reused as-is: `~/.claude/scripts/kb-*.sh`, `~/Desktop/Projects/obsidian-claude-kb/project-init.sh`, `~/.claude/hooks/gitnexus/gitnexus-hook.cjs`
