# Drift mode (re-running /project-init on a configured project)

## Protocol

1. `bash $SKILL/scripts/drift-diff.sh "$ROOT" > /tmp/drift.json`
2. `count == 0` → report "no drift", refresh `detection.lastRun`, optionally offer to re-verify stale runbooks (verified > 30 days ago). Done.
3. Otherwise present the drift table to the user: `field | configured | detected | proposed action`, grouped by category (git / tracker / database / cloud / commands / infra).
4. Approval per category via AskUserQuestion: Accept all in category / pick individually / skip. **Fields whose value carries `source: "user"` are never auto-applied** — present them as "detected differs from your manual setting — keep yours?" with keep as the default.
5. Apply accepted changes:
   - Update `project.json` fields; refresh `detection.fingerprints` + `lastRun` (always, even for skipped items — the user saw them).
   - If tracker/db/cloud type changed: re-run the relevant Phase 3 credential recipe and swap the permission fragment.
   - Regenerate `settings.local.json` permissions per `references/permissions.md` — diff first, list any rules that would be dropped, ask before removing.
6. Commands whose lockfile/CI fingerprints changed (or newly added candidates the user accepted): re-run Phase 8 verification for just those commands and update their runbooks.
7. Check `.git/info/exclude` still has the managed block (re-run `exclude-local.sh`); re-check the project became/stopped being a git repo.
8. Report what changed, what was kept, what was re-verified.

## Skipped / declined integrations

Two suppression mechanisms:
- `project.json` `detection.declined` (e.g. `["cloud.provider"]`) — fields the user explicitly declined; `drift-diff.sh` never re-proposes them. Add a field here whenever the user rejects a detected integration.
- Detection blind spots are auto-suppressed: when detection returns null for a field that config has a value for (workspace roots without their own git repo, manually-configured DBs), that is NOT drift.

New-signal exception: if a previously-declined integration's detection signal is NEW (e.g. docker-compose gained a postgres service), mention it once informationally without proposing config changes.
