---
name: review-pr
version: 2.0.0
description: |
  Review a merge request (GitLab) or pull request (GitHub) for bugs, security, and
  quality issues. Tracker type comes from the project's .claude/project.json.
  Argument: the MR/PR number. Use when asked to "review MR/PR <n>" or "/review-pr".
allowed-tools:
  - Bash
  - Read
  - Grep
---

Review the merge/pull request: $ARGUMENTS

## Step 0 — Resolve project config

Read `.claude/project.json` from the git root (or one directory above for workspace layouts) for `tracker.type`. Fallback if absent: note "No project config — run `/project-init`" and assume `gitlab` (legacy behavior).

Run all tracker CLI commands from the current working directory (the git repo root of whichever project is active).

## Step 1 — Fetch the MR/PR

**gitlab:**
1. `glab mr view $ARGUMENTS` — title, description, metadata.
2. `glab mr diff $ARGUMENTS` — full diff.
3. No argument? `glab mr list --state=opened`, show the list, ask which to review.

**github:**
1. `gh pr view $ARGUMENTS`
2. `gh pr diff $ARGUMENTS`
3. No argument? `gh pr list --state open`, ask which to review.

Then review the diff thoroughly using this checklist:

## Review Checklist

### Functionality
- Does the code do what it's supposed to do?
- Are edge cases handled?
- Is the logic correct?

### Security
- Are inputs validated and sanitized?
- Are there any injection vulnerabilities?
- Is authentication/authorization correct?
- Are secrets properly handled?

### Performance
- Are there any N+1 queries?
- Are there unnecessary loops or iterations?
- Is there appropriate caching?

### Code Quality
- Is the code readable and maintainable?
- Are names clear and consistent?
- Is there unnecessary complexity?
- Is there code duplication?

### Error Handling
- Are errors caught and handled appropriately?
- Are error messages helpful?
- Is logging sufficient for debugging?

### Testing
- Are there tests for this code?
- Are edge cases tested?
- Are the tests meaningful?

## Output Format

Start with a summary of what the MR/PR does based on its title, description, and changes.

For each issue found:
1. **Location**: File and line number
2. **Severity**: Critical / High / Medium / Low
3. **Issue**: What the problem is
4. **Impact**: Why it matters
5. **Fix**: How to resolve it

Number issues sequentially (Issue 1, Issue 2, …) — `/post-review-comments` parses these.

End with an overall verdict: Approve / Request Changes / Needs Discussion. (Verdict is advisory text only — never call approve/merge commands.)

If no issues found, confirm the code looks good and note any positive aspects.
