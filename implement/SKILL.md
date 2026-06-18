---
name: implement
version: 1.0.0
description: |
  Implement an approved spec test-first, then validate and verify it. Reads
  spec.md (the contract) plus context.md/interview.md from the task dir, syncs
  and branches, runs impact analysis, delegates the coding to a fresh sonnet
  subagent under strict TDD discipline, then independently validates the diff
  against every acceptance criterion (re-running tests/lint itself, never
  trusting the subagent's report) and verifies user-facing behavior in the
  running app. Writes validation.md + verify.md. Locates the task dir via the
  shared task-env helper. Runs standalone, or as Stage 5+6 of /work-ticket.
  Expects an approved spec — it does not write or re-open the spec, and it never
  merges, deploys, or changes ticket state.
  Use when asked to "implement <id>", "build <id> from the spec", "implement
  the spec for <id>", or "/implement <id>".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
triggers:
  - implement ticket
  - implement the spec
  - build from the spec
---

## Arguments

`$ARGUMENTS`: the `<task-id>` (ticket id or `adhoc-<slug>`). If omitted, use the task id already established in this session.

## Step 0 — Locate the task dir (shared helper)

```bash
eval "$(bash ~/.claude/skills/understand-task/scripts/task-env.sh "<task-id>")"
# $CFG and $TASK_DIR are now set
```

From `CFG` read: `commands.test`, `commands.lint`, `commands.dev`, `git.*` (targetBranch, branchPrefixes), `autonomy.*`, `stack.subprojects`.

Read `$TASK_DIR/spec.md` (the contract — required), `$TASK_DIR/context.md`, and `$TASK_DIR/interview.md`. **No `spec.md`** → stop and tell the user to run `/create-spec <id>` first; this skill implements a spec, it does not invent one.

> State note: `state.json` is owned by `/work-ticket`. Standalone, this skill just creates the branch and writes `validation.md` / `verify.md`; the orchestrator records branch + impl/verify state when it drives this skill.

## Stage A — Setup

Work inside the subproject recorded in `context.md` (workspaces); otherwise the repo root.

1. Sync and branch: `git fetch origin && git checkout <git.targetBranch> && git pull`, then create `<prefix><ticket-id>-<slug>` using the matching `git.branchPrefixes` entry for the ticket type. Ad-hoc tasks: `<prefix><slug>` (no id in the branch).
2. **Impact analysis** for the symbols the spec's approach touches (GitNexus if indexed; otherwise Grep for call sites). Surprising blast radius → note it in `spec.md` risks. These findings go into the subagent prompt — the subagent starts blind.

## Stage B — Delegate (Agent tool, `model: "sonnet"`)

Spawn one implementation subagent. It has fresh context, so the prompt must be self-contained — it cannot see this conversation. The prompt must include:

- Absolute paths to read first: `$TASK_DIR/spec.md` (the contract), `$TASK_DIR/context.md`, `$TASK_DIR/interview.md`, and `references/implement.md` in this skill's directory (the TDD discipline it must follow).
- The subproject root (cwd for all work), the branch it is on, and `commands.test` / `commands.lint` with their configured `cwd`.
- The impact-analysis findings from Stage A.
- Rules, restated verbatim: implement ONLY the spec's acceptance criteria — nothing out of scope; red→green→refactor in vertical slices, each criterion maps to at least one test; commit per slice following the repo's existing message conventions with NO `Co-Authored-By` trailers, "Generated with" lines, or any other AI attribution; a material ambiguity the spec doesn't settle → STOP and return the question instead of guessing.
- Return format: per-criterion status (implemented + test name), files changed, commits made, full-suite test/lint output, and any questions or deviations.

## Stage C — Validate (orchestrator)

The subagent's report is a claim, not evidence. Validate independently:

1. Re-read `$TASK_DIR/spec.md`, then read the full diff (`git diff <git.targetBranch>...HEAD`) and the new/changed tests.
2. Check every acceptance criterion: demonstrably implemented in the diff AND covered by a test that asserts the spec'd behavior (not implementation details). A criterion whose test would pass without the implementation change is not covered.
3. Run `commands.test` and `commands.lint` yourself in their configured `cwd` — never trust the subagent's pasted output.
4. Check the diff for scope creep (changes not traceable to a criterion or the approved approach), convention violations, and AI-attribution in commit messages (`git log <git.targetBranch>..HEAD --format='%B'`).
5. Record the verdict per criterion in `$TASK_DIR/validation.md` (pass / fail + reason).

**Fail** → send the specific findings (criterion, file, what's wrong, what the spec requires) back to the **same** subagent via SendMessage — its context is intact; do not re-explain the task — then re-validate from step 1. A material question returned by the subagent → surface it to the user (or, under `/work-ticket`, trigger an interview round), update the spec, then resume the subagent with the answer. After 3 failed rounds, stop and report to the user instead of looping. **Pass** → proceed to Stage D.

## Stage D — Verify behavior

1. Run `commands.test` and `commands.lint` in their configured `cwd`. All green is the bar; a partial/filtered run never counts. Failures → back to Stage C (send findings to the subagent, re-validate).
2. For user-facing changes with a runnable `commands.dev`: follow `references/verify.md` — start the app, exercise each acceptance criterion through the real interface, record evidence in `$TASK_DIR/verify.md`, stop the app.
3. Re-read `spec.md` acceptance criteria one by one — each is either demonstrably met or explicitly reported as not met.

## Output

Report: branch name, per-criterion status (implemented + verified, or not met + why), full test/lint result, files changed, and anything a reviewer should double-check. Do not push or open an MR — that's `/ship-it` (run by `/work-ticket`, or by the user).

## Hard rules

- Implementation code is written only by the Stage B subagent; this skill validates and never rubber-stamps — every criterion checked against the actual diff and an independent test run.
- Respect every entry in `autonomy.blocked`. No merge, no deploy, no DB writes, no ticket-state changes.
- Never guess at a material ambiguity the spec doesn't settle — stop and surface it.
- No AI attribution anywhere: no `Co-Authored-By` trailers, no "Generated with" footers in commit messages.
