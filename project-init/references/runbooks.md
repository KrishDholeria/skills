# Verified-runbook protocol

A runbook Claude has proven works is what makes later tasks independent. Unverified docs are where autonomy dies.

## Verification protocol (Phase 8)

Order: install → lint → test → build → dev. For each non-null `commands` entry:

1. Run it in its `cwd`. Capture exit code + last ~20 lines of output.
2. **dev**: run in background, poll `readyCheck` every 2s up to 60s, capture the healthy response, then kill the process (and any children).
3. Success → `project.json`: `verified = today`, `source = "verified"`. Write the runbook note (below).
4. Failure → diagnose and retry (≤3 attempts; typical fixes: missing venv, missing .env, service not running via docker compose up). Every failure + working fix goes in Troubleshooting. Still failing → runbook `status: broken`, `verified: null`, report to user, move on.
5. Long test suites: if `test` runs >10 min, verify with a scoped subset (one module) and note "full suite unverified" in the runbook.

## Note format

One note per command class: `setup-install`, `run-tests`, `dev-server`, `lint-and-build`, `db-access`, `deploy-overview` (the last documents the deploy process but is explicitly marked NOT autonomous). Saved via:

```bash
bash ~/.claude/scripts/kb-save.sh "<vault>" "runbooks" "<slug>" "<title>" "runbook,claude-context-conditional" "<content>"
```

`claude-context-conditional` keeps runbooks out of the SessionStart auto-load budget; they're pulled on demand via kb-search.

Body structure (content arg):

```markdown
status: verified | unverified | broken
verified: <date>
command: "<cmd>"
cwd: <dir>

## Purpose
## Preconditions
(venv, services that must be up, env vars)
## Steps
(exact commands, in order)
## Expected output
(captured snippet from the verification run, e.g. "847 passed in 92s")
## Troubleshooting
(every failure hit during verification + the fix that worked)
## Last verified
(date + tool versions, e.g. python 3.12.3, pytest 8.1)
```

## Self-heal contract

Lives in CLAUDE.local.md; restated here: whenever a runbook step fails during normal work, fix it, update the note (append to Troubleshooting, bump `verified`), and sync the matching `project.json` `commands.*.verified` date.
