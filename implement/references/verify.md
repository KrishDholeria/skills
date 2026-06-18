# Behavior verification

Tests passing is necessary, not sufficient — for user-facing changes, observe the changed behavior in the running app before claiming done. Self-contained — no external skill needed.

## Protocol

1. **Start** the app with `commands.dev` from project.json (in its `cwd`), in the background. Poll the configured `readyCheck` (or the dev `url`) until it answers, up to 60s. No `commands.dev` or it can't start → record that verification was test-only in the final report; don't fake it.
2. **Exercise each acceptance criterion** through the real interface:
   - API change → `curl` the actual endpoint(s): the happy path, one boundary case, and one invalid input. Capture status + response body.
   - UI change → if a browser tool/skill is available in the session, drive the changed flow and screenshot; otherwise verify the API/data layer it sits on and record the UI as visually unverified.
   - Job/command change → run it once against safe data and inspect its output/side effects.
3. **Check the blast radius**: exercise one adjacent behavior that shares the code you touched (per the impact analysis) to confirm it still works.
4. **Watch the logs** while exercising — new warnings/errors caused by the change count as failures even when responses look right.
5. **Stop** the dev server and any other process you started.

## Evidence

For each acceptance criterion record in `$TASK_DIR/verify.md`: the command/action, the observed result, met / not met. This feeds the final report and the MR description — reviewers get evidence, not assurances.

## Rules

- Never mark tests passed from a partial or filtered test run.
- A criterion that can't be exercised (needs prod data, external service, missing access) is reported as **not verified, and why** — it is never silently counted as met.
- Verification failures go back to the implementation loop; don't patch around them in the verify step.
