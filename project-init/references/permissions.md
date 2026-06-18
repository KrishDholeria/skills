# Composing settings.local.json from permission fragments

## Selection

| Condition | Fragment |
|---|---|
| always | `base.json`, `git.json` |
| `tracker.type` set | `tracker-<type>.json` |
| `database.engine` set | `db-<engine>.json` |
| `cloud.provider` set | `cloud-<provider>.json` |

## Rendering rules

1. Strip every `_comment` key.
2. Placeholder substitution from `project.json`: `{{PROJECT_ROOT}}`, `{{DB_HOST}}`, `{{AWS_PROFILE}}`, `{{GCP_CONFIG}}`, `{{STAGING_URL}}`, `{{CMD_TEST}}`/`{{CMD_LINT}}`/`{{CMD_BUILD}}`/`{{CMD_INSTALL}}`.
3. Multipliers: a rule containing `{{PROTECTED}}` is emitted once per `git.protectedBranches` entry; `{{PREFIX}}` once per `git.branchPrefixes`; `{{STAGING_URL}}` once per environment URL.
4. Drop allow rules whose substituted value is null/empty (e.g. no build command → no build allow).
5. Concatenate all `allow` arrays and all `deny` arrays, dedupe, sort. Output shape:

```json
{
  "permissions": {
    "allow": [...],
    "deny": [...]
  }
}
```

6. Existing `settings.local.json`: parse it, keep keys other than `permissions` untouched, and for permissions diff old vs generated — list rules that would be dropped and ask the user before removing (hand-added rules may be intentional). Never carry over rules that embed secrets (e.g. `PGPASSWORD=...`) — flag them for deletion explicitly.

## Layering reminder

Deny rules in `~/.claude/settings.json` (global baseline) always win over project allows. The autonomy boundary is enforced three ways where possible: deny rule + skill-text refusal + credential that cannot do it. Tracker merge/state-change has no credential layer (GitLab `api` scope is coarse) — that residual risk is accepted and documented.
