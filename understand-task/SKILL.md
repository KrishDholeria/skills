---
name: understand-task
version: 1.0.0
description: |
  Understand a tracker ticket (or a free-text task) and gather everything needed
  to write a correct spec. Fetches the ticket and its comments/links, then gathers
  context from the knowledge base, the code graph, linked docs, and the web —
  writing two artifacts to the task dir: ticket.md (the primary source) and
  context.md (relevant code, KB findings, external docs, tech notes, and gaps).
  This is the foundational step of the work-ticket suite: it CREATES the task dir
  (<root>/.claude/tasks/<id>/) that create-spec and implement later read from.
  Runs standalone, or as Stage 1+2 of /work-ticket.
  Also works without a ticket: pass a free-text task description instead of an id
  and it builds the task brief from the prompt (ad-hoc mode).
  Use when asked to "understand ticket <id>", "research ticket <id>", "gather
  context for <id>", "/understand-task <id>", or "/understand-task <description>".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - WebSearch
  - WebFetch
  - Skill
  - Agent
triggers:
  - understand ticket
  - research ticket
  - gather context for
  - understand task
---

## Arguments

`$ARGUMENTS`: either a `<ticket-id>` (tracker ticket) **or a free-text task description** (ad-hoc mode — no ticket exists, the prompt IS the task).

Disambiguation, in order:

1. Argument looks like a ticket id (a number, or `PREFIX-123` style key) → tracker intake.
2. Anything else (a sentence, a paragraph, a pasted Slack message) → **ad-hoc intake**. Derive the task id now: `adhoc-<slug>` where slug is a 3–6 word kebab-case summary. Use this id everywhere a ticket id is used below.

## Step 0 — Resolve config and create the task dir

This skill owns task-dir creation for the whole suite. Resolve `.claude/project.json` at the git root (or one directory above it, for workspace layouts), then create the task dir:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CFG=""
for c in "$ROOT/.claude/project.json" "$(dirname "$ROOT")/.claude/project.json"; do
  [ -f "$c" ] && CFG="$c" && break
done
# No config → stop with: "No .claude/project.json found — run /project-init first."
TASK_DIR="$(dirname "$(dirname "$CFG")")/.claude/tasks/<ticket-id>"
mkdir -p "$TASK_DIR"
```

From `CFG` read what the steps below need: `tracker.*`, `kb.vaultPath`, `stack.subprojects`.

**If no config**: stop with "No `.claude/project.json` found — run `/project-init` first." This skill does not improvise tracker access.

> State note: `state.json` is owned by `/work-ticket` (the orchestrator). When run standalone, this skill writes only the `ticket.md` / `context.md` artifacts — no `state.json`. Downstream skills locate this same task dir via `understand-task/scripts/task-env.sh`.

## Stage 1 — Intake

Fetch the ticket and everything attached to it.

**Ad-hoc mode (task given as a prompt, no ticket)** — skip the tracker entirely:

1. Write `$TASK_DIR/ticket.md` from the prompt: a one-line title, the **full prompt verbatim** as the description (never paraphrase it away — it is the only primary source), and the same extracted-links list as below for any URLs the prompt contains.
2. Classify the task type (feature/bug/chore) from the prompt and note it at the top of `ticket.md`.
3. A thin prompt is not a blocker — it just shifts weight onto Stage 2 exploration and the later interview. Expect ad-hoc tasks to surface more open questions than tickets do.

Then continue at Stage 2.

**tracker.type = gitlab** (issues may live in a separate tracker project — use `tracker.project`, not `repoProject`):

```bash
PROJECT_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('<tracker.project>', safe=''))")
glab api "projects/$PROJECT_ENC/issues/<id>" > "$TASK_DIR/ticket.json"
glab api "projects/$PROJECT_ENC/issues/<id>/notes?per_page=100&sort=asc" > "$TASK_DIR/notes.json"
```

**tracker.type = github**: `gh issue view <id> --repo <tracker.repoProject> --json number,title,body,labels,comments,url`

Write `$TASK_DIR/ticket.md`: title, full description, every comment (author + date), labels, and an **extracted links list** — every URL found in description/comments, classified (Google Doc, design file, MR/issue reference, other). Note the ticket type (from labels/title) at the top.

## Stage 2 — Context

Goal: everything needed to write a correct spec, written to `$TASK_DIR/context.md`. Gather from every relevant source; record what could NOT be read in an **Open questions / gaps** section — never silently skip a source.

1. **Knowledge base**: `bash ~/.claude/scripts/kb-search.sh "<ticket keywords>" <vault>` (script missing → Grep the vault path directly). Pull in relevant decisions, runbooks, integration notes.
2. **Code**: locate the code the ticket touches. Use GitNexus (graph queries / impact analysis) when indexed; otherwise Grep/Glob exploration. For workspaces, determine which subproject this ticket belongs to and **record it explicitly in `context.md`** (downstream skills read the subproject from here).
3. **Linked docs** (from the Stage 1 links list): `bash ~/.claude/skills/fetch-doc/scripts/fetch-doc.sh "<url>"` — converts Google Docs/Sheets/Slides to export endpoints, tries anonymous access, then the one-time cookie file (setup in the fetch-doc skill). Public non-Google pages → WebFetch also works. Exit 2/3 (auth) → relay the setup steps once, add the doc to the gaps section, continue.
4. **Unfamiliar tech**: if the ticket involves a library/API/pattern not evidenced in the codebase or KB, research it (WebSearch/WebFetch) and summarize the relevant parts — enough to implement correctly, not a tutorial.

`context.md` sections: **Ticket summary** · **Subproject** (which repo/package, for workspaces) · **Relevant code** (files + how they connect) · **KB findings** · **External docs** · **Tech notes** · **Open questions / gaps** (everything unread, plus anything material the ticket/docs/code did not settle — this is the candidate list the interview later resolves).

## Output

Two artifacts in `$TASK_DIR`: `ticket.md` (primary source) and `context.md` (everything needed to spec). Report where they were written and a one-paragraph summary of what the task is and the biggest open questions, so the user can decide whether to interview, spec, or hand to `/work-ticket`.

## Hard rules

- Never fabricate context: anything unread goes in the **Open questions / gaps** section of `context.md` and must surface to whatever writes the spec.
- Never improvise tracker access or guess at config — if `project.json` is missing, stop.
- This skill gathers and understands; it does not write a spec, interview the user, or change any code.
