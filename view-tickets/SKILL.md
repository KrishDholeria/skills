---
name: view-tickets
version: 2.0.0
description: |
  Fetch and display the project's tracker board for the current iteration/sprint,
  grouped by status. Tracker type and board identifiers come from the project's
  .claude/project.json. Use when asked to "view tickets", "show the board",
  "what's in this sprint", or "/view-tickets".
allowed-tools:
  - Bash
---

## Step 0 — Resolve project config

Read `.claude/project.json` from the git root (or one directory above it for workspace layouts; or the current directory if not a git repo). Required fields: `tracker.type` plus the type-specific fields below.

**If no config or no tracker section**: stop with "No tracker configured for this project — run `/project-init` to set it up." Board IDs are not guessable; do not improvise.

`$ARGUMENTS` (optional): a status name (e.g. "In Progress") or a username — filter the displayed results accordingly.

## tracker.type = gitlab

Uses `tracker.project` (namespace path), `tracker.iterationCadenceId`, `tracker.statusLabels` (ordered list).

```bash
PROJECT_ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote('<tracker.project>', safe=''))")
glab api "projects/$PROJECT_ENC/issues?iteration_cadence_id=<tracker.iterationCadenceId>&iteration_id=Current&per_page=100&state=opened" > /tmp/tickets.json
```

If `iterationCadenceId` is null, fall back to `glab api "projects/$PROJECT_ENC/issues?state=opened&per_page=100"`.

Then group and render with python3: group issues by the first matching label from `tracker.statusLabels` (in order; unmatched → "No Status"). For each group print `### <status without prefix> (<count>)`, then per ticket: `- #<iid> **<title>** [<type-label>] (@<assignee or unassigned>)` plus the web URL on the next line. (Strip a `Status::` prefix for display if present.)

## tracker.type = github

Uses `tracker.repoProject`. GitHub has no iterations; use the most recent open milestone if one exists, else all open issues.

```bash
gh issue list --repo <tracker.repoProject> --state open --limit 100 --json number,title,labels,assignees,url,milestone
```

Group by `tracker.statusLabels` if configured (project-board status labels), else by milestone.

## tracker.type = jira

Uses `tracker.boardId`.

```bash
jira sprint list --current --board <tracker.boardId> --plain 2>/dev/null || jira issue list --plain
```

Group by the Status column.

## Final summary (all trackers)

After displaying the grouped tickets:
- Total open tickets
- Breakdown by status
- Any blocked tickets (highlight these)
- Tickets assigned to the current user if identifiable

Read-only: never close, reopen, relabel, assign, or otherwise mutate tickets from this skill.
