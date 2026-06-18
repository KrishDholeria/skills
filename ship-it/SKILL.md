---
name: ship-it
version: 2.0.0
description: |
  Push the current branch, generate a structured MR/PR description, and create or
  update a draft merge request (GitLab) or pull request (GitHub). Stack and target
  branch come from the project's .claude/project.json. If an MR/PR already exists
  for the current branch, updates it instead of creating a new one.
  Accepts an optional target branch name as the first argument (e.g. /ship-it main).
  Use when asked to "ship it", "open a PR", "create a draft MR", "push and open MR", or "ship-it".
allowed-tools:
  - Bash
  - Read
  - mcp__gitnexus__detect_changes
triggers:
  - ship it
  - open a pr
  - create a draft mr
  - push and open mr
---

## Step 0 — Resolve project config

Find the config: `.claude/project.json` at the git root (`git rev-parse --show-toplevel`). In workspace layouts (the repo you're in is a sub-repo of a parent workspace), also check one directory above the git root.

```bash
ROOT=$(git rev-parse --show-toplevel)
CFG=""
for c in "$ROOT/.claude/project.json" "$(dirname "$ROOT")/.claude/project.json"; do
  [ -f "$c" ] && CFG="$c" && break
done
```

From `CFG` read: `git.targetBranch`, `git.protectedBranches`, `git.branchPrefixes`, `tracker.type` (`gitlab` → `glab`, `github` → `gh`).

**Fallbacks when no config exists**: tell the user "No `.claude/project.json` found — run `/project-init` to set this project up", then continue with legacy defaults: tracker `gitlab`, target branch `develop`, protected branches `main`+`develop`, standard prefixes (`feature/ bugfix/ hotfix/ chore/ docs/ refactor/ test/`).

```bash
BRANCH=$(git branch --show-current)
BASE="${ARGS:-<git.targetBranch from config>}"   # explicit argument always wins
```

## Step 1 — Gather git context

**If `BRANCH` is in `git.protectedBranches`**, do not ship directly from a protected branch.

First, read the current diff to understand what changed:

```bash
git diff --stat HEAD
git log --oneline -10
git status --short
```

Based on the changes, suggest a branch name using the prefixes from `git.branchPrefixes`:

| Prefix | Use for |
|--------|---------|
| `feature/` | New features |
| `bugfix/` | Non-critical bug fixes |
| `hotfix/` | Urgent production fixes |
| `chore/` | Maintenance, deps, config |
| `docs/` | Documentation updates |
| `refactor/` | Code restructuring, no behavior change |
| `test/` | Adding or fixing tests |

Present the suggestion and ask:
> "You're on `<BRANCH>`, which is a protected branch. Based on your changes, I suggest: `<suggested-branch-name>`. Use this name, or provide your own?"

Wait for the user's response. Validate a custom name starts with a configured prefix; if not, ask them to rename. Then:

```bash
git checkout -b <confirmed-branch-name>
BRANCH=<confirmed-branch-name>
```

Then collect the comparison context:

```bash
echo "=== BRANCH ===" && echo "$BRANCH"
echo "=== TARGET ===" && echo "$BASE"
echo "=== STATUS ===" && git status --short
echo "=== COMMITS vs $BASE ===" && git log origin/$BASE..HEAD --oneline 2>/dev/null || git log $BASE..HEAD --oneline
echo "=== DIFF STAT vs $BASE ===" && git diff origin/$BASE...HEAD --stat 2>/dev/null || git diff $BASE...HEAD --stat
echo "=== FULL DIFF vs $BASE ===" && git diff origin/$BASE...HEAD 2>/dev/null || git diff $BASE...HEAD
```

**If git status shows uncommitted changes**, warn the user:
> "You have uncommitted changes. Commit or stash them before shipping, or I can commit them for you — what would you like to do?"
Stop and wait for their response before continuing.

**When committing**, never add a `Co-Authored-By` trailer to the commit message.

## Step 2 — GitNexus change detection (optional enrichment)

Call `mcp__gitnexus__detect_changes` with `{"scope": "compare", "base_ref": "<BASE>"}` to get a symbol-level summary. Use it to enrich the description. Skip gracefully if the index is stale or the tool errors.

## Step 3 — Push the branch

```bash
git push -u origin HEAD
```

If the push fails, report the exact error and stop. Never force-push.

## Step 4 — Generate the description

Using the diff, commit log, and GitNexus output, write a description following this exact template:

```
## Summary
<1–2 sentences: WHAT changed and WHY — the motivation, not a restatement of the diff>

## Changes
<bullet list — each item: `path/or/symbol` — what changed and why it matters>

## How to Test
1. <concrete step — what to run or click>
2. <expected result>
<add steps as needed; if purely backend, include curl/API call examples>

## Screenshots
<UI changes only — otherwise delete this section>

## Notes / Caveats
<edge cases, follow-up tickets, known limitations — delete if none>

## Related
<"Closes #N" or "Relates to #N" if applicable — otherwise delete>
```

Rules:
- Summary explains the *why*, not the what — reviewers can read the diff
- Test steps must be concrete: "run X, expect Y"
- Do not fabricate related issues — omit that section if none are known
- If test steps are unclear from context, write "TODO: add test steps" rather than guessing

## Step 5 — Show draft and confirm

Print the full generated description and ask:
> "Here's the draft description. Reply **yes** to create it, or paste edits and I'll update it."

Wait for confirmation.

## Step 6 — Create or update (dispatch on tracker.type)

**Always write the description to a temp file first**, then pass via `$(cat /tmp/mr_desc.md)` — avoids shell escaping issues with backticks. Never inline the description or escape backticks.

```bash
cat > /tmp/mr_desc.md << 'EOF'
<approved description with backticks unescaped>
EOF
```

### tracker.type = gitlab

```bash
glab mr list --source-branch "$BRANCH"
```

If an MR exists:
```bash
glab mr update <MR_NUMBER> --title "<branch name in title-case, spaces for hyphens>" --description "$(cat /tmp/mr_desc.md)"
```

If not, create a draft:
```bash
glab mr create \
  --title "<branch name in title-case, spaces for hyphens>" \
  --description "$(cat /tmp/mr_desc.md)" \
  --target-branch "$BASE" \
  --draft \
  --squash-before-merge \
  --remove-source-branch
```

### tracker.type = github

```bash
gh pr list --head "$BRANCH"
```

If a PR exists:
```bash
gh pr edit <PR_NUMBER> --title "<title>" --body "$(cat /tmp/mr_desc.md)"
```

If not, create a draft:
```bash
gh pr create --title "<title>" --body "$(cat /tmp/mr_desc.md)" --base "$BASE" --draft
```

## Step 7 — Done

Report: branch pushed, MR/PR created or updated as draft targeting `$BASE`, and paste the URL. Never merge it — merging is always the user's action.
