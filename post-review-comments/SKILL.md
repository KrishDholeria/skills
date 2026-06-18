---
name: post-review-comments
version: 2.0.0
description: |
  Post specific issues from a /review-pr review as MR/PR comments (inline where the
  issue has a file:line location, general note otherwise). Tracker type and project
  come from .claude/project.json. Arguments: <mr_or_pr_number> <issue_numbers...>
  e.g. "1266 1 2 3". Use after /review-pr when asked to post review comments.
allowed-tools:
  - Bash
---

Post the specified review issues from the most recent `/review-pr` output as comments.

**Arguments:** `$ARGUMENTS`

## Step 0 — Resolve project config

Read `.claude/project.json` (git root, or one directory above for workspaces): `tracker.type`, `tracker.repoProject` (namespace/repo of the code repository — NOT the ticket tracker project). Fallback if absent: assume gitlab and resolve the project from the MR URL via `glab mr view` (legacy behavior).

This is the only skill permitted to POST via the tracker's API — and only to the discussions/notes/comments endpoints shown below. Never POST anywhere else.

## Step 1 — Parse arguments

Split `$ARGUMENTS` on spaces and/or commas. First token = MR/PR number; remaining tokens = issue numbers to post. Missing either → ask the user.

## Step 2 — Extract issues from conversation context

Find the most recent `/review-pr` output in this conversation. Issues follow:

```
#### Issue N — Severity
**Location**: file:line   ← may be absent
**Severity**: ... **Issue**: ... **Impact**: ... **Fix**: ...
```

Extract only the requested issue numbers, preserving full text exactly.

## Step 3 — Format each comment body

```
**[<Severity>] <one-line summary>**

<what the problem is>

**Impact:** <why it matters>

**Fix:** <how to resolve it>
```

Keep backticks and code fences exactly as written — do not escape them.

## Step 4 — Post (dispatch on tracker.type)

### gitlab

Resolve the numeric project ID and diff refs directly from `tracker.repoProject`:

```bash
PROJECT_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('<tracker.repoProject>', safe=''))")
glab api "projects/$PROJECT_ENC/merge_requests/<mr_number>" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('project_id:', d['project_id'])
r = d['diff_refs']
print('base_sha:', r['base_sha']); print('head_sha:', r['head_sha']); print('start_sha:', r['start_sha'])
"
```

For each issue, build and post comments in ONE python3 script (avoids shell-escaping issues):

```python
import json, subprocess

PROJECT_ID = <id>; MR_IID = <mr_number>
BASE_SHA = "<base_sha>"; HEAD_SHA = "<head_sha>"; START_SHA = "<start_sha>"
HDR = "Content-Type: application/json"
DISC_EP = f"projects/{PROJECT_ID}/merge_requests/{MR_IID}/discussions"
NOTE_EP = f"projects/{PROJECT_ID}/merge_requests/{MR_IID}/notes"

def post(endpoint, payload):
    r = subprocess.run(["glab", "api", endpoint, "--method", "POST", "--header", HDR, "--input", "-"],
                       input=json.dumps(payload).encode(), capture_output=True)
    ok = r.returncode == 0 and r.stdout.strip()
    print("  OK" if ok else f"  ERR {r.stderr.decode()[:200]}")
    return bool(ok)

def post_inline(body, file_path, old_line=None, new_line=None):
    # removed line (- in diff) -> old_line; added line (+) -> new_line
    position = {"base_sha": BASE_SHA, "start_sha": START_SHA, "head_sha": HEAD_SHA,
                "position_type": "text", "old_path": file_path, "new_path": file_path}
    if old_line: position["old_line"] = old_line
    if new_line: position["new_line"] = new_line
    if not post(DISC_EP, {"body": body, "position": position}):
        print("  Falling back to general note..."); post(NOTE_EP, {"body": body})

def post_note(body):
    post(NOTE_EP, {"body": body})
```

Issues with `Location: file:line` → `post_inline` (inspect the diff to decide old_line vs new_line); without → `post_note`.

### github

```bash
gh pr view <pr_number> --repo <tracker.repoProject> --json headRefOid -q .headRefOid   # commit_id for inline comments
```

```python
import json, subprocess

REPO = "<tracker.repoProject>"; PR = <pr_number>; COMMIT = "<headRefOid>"

def gh_api(endpoint, payload):
    r = subprocess.run(["gh", "api", endpoint, "--method", "POST", "--input", "-"],
                       input=json.dumps(payload).encode(), capture_output=True)
    print("  OK" if r.returncode == 0 else f"  ERR {r.stderr.decode()[:200]}")
    return r.returncode == 0

def post_inline(body, path, line):
    ok = gh_api(f"repos/{REPO}/pulls/{PR}/comments",
                {"body": body, "commit_id": COMMIT, "path": path, "line": line, "side": "RIGHT"})
    if not ok:
        post_note(body)

def post_note(body):
    gh_api(f"repos/{REPO}/issues/{PR}/comments", {"body": body})
```

## Step 5 — Report results

```
Posted N comment(s) on !<number>:
  Issue 1 → inline at <file>:<line>  ✓
  Issue 2 → general note             ✓
```

If any post failed, show the error and the comment text so the user can post it manually.
