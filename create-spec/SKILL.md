---
name: create-spec
version: 1.0.0
description: |
  Turn what's known about a task into a precise, testable spec.md. Reads the
  persisted artifacts in the task dir (ticket.md, context.md, and interview.md
  if present) AND the current session context, then writes spec.md: problem,
  numbered acceptance criteria (each tagged with its source), out-of-scope,
  approach, test plan, and risks. Locates the task dir via the shared task-env
  helper; if understand-task has not run, it still creates the dir and works
  from session context alone. Runs standalone, or as Stage 4 of /work-ticket.
  Does NOT include the approval gate — /work-ticket owns that.
  Use when asked to "write a spec for <id>", "spec out <id>", "create-spec <id>",
  or "/create-spec <id>".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
triggers:
  - write a spec for
  - spec out
  - create spec for
---

## Arguments

`$ARGUMENTS`: the `<task-id>` (ticket id or `adhoc-<slug>`). If omitted, use the task id already established in this session (the one `understand-task` or `/work-ticket` just worked on). Only one task is in play per session unless an id is passed explicitly.

## Step 0 — Locate the task dir (shared helper)

```bash
eval "$(bash ~/.claude/skills/understand-task/scripts/task-env.sh "<task-id>")"
# now $CFG and $TASK_DIR are set; $TASK_DIR is created if it did not exist
```

If the helper errors (no `project.json`), relay its message and stop.

## Inputs

Read whatever exists — these are the raw material for the spec:

1. `$TASK_DIR/ticket.md` — the primary source (what was asked).
2. `$TASK_DIR/context.md` — relevant code, KB findings, external docs, tech notes, and **Open questions / gaps**.
3. `$TASK_DIR/interview.md` — resolved ambiguities. Answers here are **requirements with source "user"** and override anything inferred from docs or code.
4. **The current session context** — anything discussed, discovered, or decided in this conversation that isn't yet on disk. Fold it in; it is as authoritative as the artifacts.

Missing artifacts are not a blocker — work from whatever is present plus session context. If `ticket.md` and `context.md` are both absent and the session has no task detail either, say so and ask the user to run `/understand-task <id>` first rather than inventing a spec.

## Write `$TASK_DIR/spec.md`

- **Problem** — one paragraph, in domain language.
- **Acceptance criteria** — numbered, testable; mark each one's source: ticket, interview answer, or inferred.
- **Out of scope** — explicit, especially adjacent cleanups.
- **Approach** — files to change, new components, data-model impact, rollout notes. Name the subproject (from `context.md`) if it's a workspace.
- **Test plan** — which acceptance criteria get automated tests, and at what level.
- **Risks & open questions** — every unresolved gap from `context.md` and every assumption made on the user's behalf.

## Output

Report where `spec.md` was written and a compact summary (problem, criteria count, key risks). Do **not** ask for approval or change any code — when run under `/work-ticket`, the orchestrator runs the approval gate; standalone, the user reads `spec.md` and decides what's next.
