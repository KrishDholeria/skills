# Detection cookbook

`detect-stack.sh` output → `project.json` field mapping, plus how to interpret weak signals.

| Signal | Field | Notes |
|---|---|---|
| `git.remote` contains `gitlab`/`github` | `tracker.type`, `tracker.cli` | Bitbucket/Jira: not remote-detectable — interview. |
| remote path minus host/`.git` | `tracker.repoProject` | The CODE repo. The ticket project may differ (e.g. code lives in `group/api` while tickets are tracked in `group/project-management/tracker`) — always confirm in the interview. |
| `subRepos[]` non-empty, root not git | workspace layout | `project.json` at workspace root; `stack.subprojects` from subRepos + manifest dirs. Tracker may differ per sub-repo — pick the primary, note others in CLAUDE.local.md. |
| `commandCandidates[]` | `commands.*` | Multiple candidates per kind in monorepos — interview which is canonical, or record per-subproject commands in the runbook and the canonical one in `commands`. npm `start` vs `dev`: prefer `dev`. |
| `database.engine` from docker-compose image or .env keys | `database.*` | Host/port default to localhost + engine default; the actual DB names need the interview (or `\l` after credentials exist). |
| `cloud.provider` from terraform providers or SDK deps | `cloud.provider` | SDK-dep detection is weak (a lib may be unused) — confirm in interview. |
| `ci` file | `commands.lint`/`test` cross-check | If CI runs a different test command than detected, prefer CI's (it's the enforced one). |

## What is never detectable (always interview)

Board/iteration IDs, ticket-project path, staging URLs, DB names, cloud profile names, project description, which subproject is "primary".

## Language fallback

If `languages` is empty but source files exist, infer from extensions (`*.py` → python, `*.ts`/`*.js` → javascript, etc.) before asking.
