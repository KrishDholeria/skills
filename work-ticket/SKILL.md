---
name: work-ticket
version: 2.0.0
description: |
  Drive a tracker ticket end-to-end by orchestrating the work-ticket skill suite:
  understand-task (intake + context) → grill-me (interview) → create-spec → a
  human spec-approval gate → implement (TDD build + validate + verify) → ship-it
  (draft MR/PR) → learn. This skill is the orchestrator: it owns the pipeline
  state in <root>/.claude/tasks/<id>/state.json (so any session can resume where
  the last one stopped) and the approval gate; each stage's real work lives in
  its own standalone skill, reused here. Tracker, commands, and autonomy
  boundaries come from the project's .claude/project.json.
  Also works without a ticket: pass a free-text task description instead of an id
  and the understand-task stage builds the task brief from the prompt (ad-hoc
  mode); the rest of the pipeline is identical.
  Use when asked to "work on ticket <id>", "pick up ticket <id>", "implement
  ticket <id>", "/work-ticket <id>", or "/work-ticket <task description>".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Skill
  - Agent
  - AskUserQuestion
triggers:
  - work on ticket
  - pick up ticket
  - implement ticket
  - work on task
---

## What this skill is

A thin orchestrator. The substance of each stage lives in a standalone skill that can also be run on its own:

| Stage | Delegated to | Produces |
|---|---|---|
| 1 Understand (intake + context) | `understand-task` | `ticket.md`, `context.md` |
| 2 Interview | `grill-me` (+ persist step here) | `interview.md` |
| 3 Spec | `create-spec` | `spec.md` |
| — Spec approval gate | **this skill** | `state.spec.approved` |
| 4 Implement + verify | `implement` | code, `validation.md`, `verify.md` |
| 5 Ship | `ship-it` | draft MR/PR |
| 6 Learn | **this skill** | KB note, final report |

This skill owns only what the suite skills can't: the resumable `state.json`, the approval gate, the interview-persistence step, and the final learn/report. It writes no implementation code and gathers no context itself — it sequences the skills and tracks progress.

## Arguments

`$ARGUMENTS`: either a `<ticket-id>` **or a free-text task description** (ad-hoc mode). Optionally `--stage <understand|interview|spec|implement|ship|learn>` to jump to a stage (artifacts from earlier stages are read from disk).

Disambiguation, in order:

1. Argument exactly matches an existing directory under `.claude/tasks/` → **resume that task** (also how ad-hoc tasks resume: `/work-ticket adhoc-<slug>`).
2. Argument looks like a ticket id (number, or `PREFIX-123` style key) → tracker task.
3. Anything else (a sentence, a paragraph) → **ad-hoc task**; the task id is `adhoc-<slug>` (3–6 word kebab-case summary). Use this id everywhere below.

## Step 0 — Resolve config and task dir

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CFG=""
for c in "$ROOT/.claude/project.json" "$(dirname "$ROOT")/.claude/project.json"; do
  [ -f "$c" ] && CFG="$c" && break
done
# No config → stop: "No .claude/project.json found — run /project-init first."
TASK_DIR="$(dirname "$(dirname "$CFG")")/.claude/tasks/<ticket-id>"
mkdir -p "$TASK_DIR"
```

(The suite skills resolve the same `TASK_DIR` from the same id via `understand-task/scripts/task-env.sh`, so every stage lands in this one directory.)

## State (owned by this skill)

`$TASK_DIR/state.json` is the single source of truth for pipeline progress. The ship gate (`project-init/scripts/ship-gate.py`, wired into the project's `settings.local.json` by /project-init) reads it to block MR/PR creation until the gates below are green.

```json
{
  "version": 1,
  "ticket": {"id": "", "title": "", "url": "", "type": "feature|bug|chore", "source": "tracker|prompt"},
  "stage": "understand",
  "completedStages": [],
  "subproject": null,
  "branch": null,
  "spec": {"approved": false, "approvedAt": null},
  "impl": {"validated": false, "rounds": 0},
  "verify": {"testsPassed": false, "lintPassed": false, "lastRun": null},
  "ship": {"mrUrl": null},
  "contextGaps": [],
  "startedAt": "", "updatedAt": ""
}
```

**Resume rule**: if `state.json` exists, report the current stage and what is already on disk (`ticket.md`, `context.md`, `interview.md`, `spec.md`, `validation.md`, `verify.md`), then continue from `stage`. Never redo a completed stage unless the user asks.

**After every stage**: append the stage to `completedStages`, set `stage` to the next, refresh `updatedAt` (one `python3 -c` json edit). The suite skills do NOT touch `state.json` — this orchestrator reads their artifacts and records the result.

## Stage 1 — Understand (delegate to `understand-task`)

Invoke the **understand-task** skill with the ticket id / task description. It creates the task dir, fetches the ticket (or builds the brief from the prompt in ad-hoc mode), gathers context, and writes `ticket.md` + `context.md`.

Then update `state.json` from the artifacts: set `ticket.*` (from `ticket.md`), `subproject` (from `context.md`), and copy the **Open questions / gaps** from `context.md` into `contextGaps`. Mark stage complete.

## Stage 2 — Interview (delegate to `grill-me`, then persist)

1. Collect the interview candidates: the `contextGaps` that affect scope, plus missing/ambiguous/conflicting acceptance criteria, undefined edge cases, and any conflicts between what the ticket says and what the code actually does.
2. **Admission rule**: a question earns its place only if (a) it cannot be answered by exploring code/docs/KB — explore first — and (b) the answer changes what gets built. Questions with a conventional default are not asked; take the default and record it for the spec.
3. Nothing material unclear → write "no open questions" to `$TASK_DIR/interview.md` and skip to Stage 3.
4. Otherwise invoke the **grill-me** skill, seeded with the candidate questions, to run the interview branch by branch with recommended answers. grill-me drives the conversation; it does not write to disk.
5. **Persist the outcome** (this skill's job): when the interview converges, write `$TASK_DIR/interview.md` — every question → answer → implication. Answers are requirements with source "user" and override anything inferred from docs or code. "You decide" / "don't know" → make the call and record it as an explicit **assumption** (it flows into the spec's Risks). Mark stage complete.

## Stage 3 — Spec (delegate to `create-spec`)

Invoke the **create-spec** skill with the task id. It reads `ticket.md` + `context.md` + `interview.md` (and the current session context) and writes `$TASK_DIR/spec.md`. Mark stage complete.

## Gate — Spec approval (hard stop, owned here)

Present a compact summary of `spec.md` (problem, criteria, approach, risks) and ask via AskUserQuestion: **Approve** / **Revise** / **Abort**.

- **Revise** → collect corrections. If they open new decision branches, run another Stage 2 interview round (grill-me + persist), have `create-spec` regenerate, and re-ask.
- **Approve** → set `spec.approved=true` and `spec.approvedAt` in `state.json`.

The ship gate makes this mandatory — no MR can be created while `spec.approved` is false. Do not proceed past this point without approval.

## Stage 4 — Implement + verify (delegate to `implement`)

Invoke the **implement** skill with the task id. It branches, runs impact analysis, delegates the build to a fresh sonnet subagent under TDD, validates the diff against every acceptance criterion (re-running tests/lint itself), and verifies user-facing behavior — writing `validation.md` + `verify.md`.

When it returns, update `state.json` from its result: `branch`, `impl.validated`, `impl.rounds`, `verify.testsPassed` / `verify.lintPassed` / `verify.lastRun`. If `implement` surfaced a material question, it routes back through a Stage 2 interview round here. Do not mark verify passed on a partial run. Mark stage complete only when implement reports all criteria met and the full suite green.

## Stage 5 — Ship (delegate to `ship-it`)

Invoke the **ship-it** skill (push, MR/PR description, draft status, config resolution). Ensure the description references the ticket (`Closes #<id>` / ticket URL) and summarizes spec + test evidence. Ad-hoc tasks have no ticket — omit the Related section (never fabricate an issue number); the spec summary carries the "why". Record the MR/PR URL in `state.ship.mrUrl`.

**Never** change ticket state, assignees, or labels — `autonomy.blocked` includes `ticket-state-change`; the human moves the board.

## Stage 6 — Learn (owned here)

1. Anything reusable and non-obvious discovered during the task (integration quirk, decision rationale, gotcha) → save to the project vault (`kb-save.sh`, or Write directly using the standard frontmatter).
2. Set `stage: "done"`. Report: MR URL, what to review first, acceptance-criteria status, and any `contextGaps` the reviewer should double-check.

## Hard rules

- No MR/PR before `spec.approved=true` and `verify.testsPassed=true` (enforced by the ship gate, but do not rely on the hook — follow the order).
- This skill orchestrates; it writes no implementation code and gathers no context itself. The substance lives in the delegated skills, which it never rubber-stamps — it records each stage's result into `state.json` from the artifacts on disk.
- Respect every entry in `autonomy.blocked`. No merge, no deploy, no DB writes, no ticket-state changes.
- Never fabricate context: anything unread stays in `contextGaps` and surfaces in the spec's risks and the final report.
- Never guess at a material ambiguity — it goes through the Stage 2 interview. A deferred choice ("you decide") is made but recorded as an explicit assumption, never silently.
- One ticket = one task dir = one branch. Parallel tickets get separate /work-ticket runs.
- No AI attribution anywhere: no `Co-Authored-By` trailers in commits, no "Generated with" footers in commit messages or MR/PR descriptions.
