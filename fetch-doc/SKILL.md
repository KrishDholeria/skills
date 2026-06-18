---
name: fetch-doc
version: 1.0.0
description: |
  Read a document URL as plain text — Google Docs, Sheets, and Slides links are
  converted to their export endpoints (txt/csv); any other URL is fetched
  directly. Tries anonymous access first; auth-walled Google docs use a
  one-time exported cookie file from ~/.claude/secrets/. Used by /work-ticket's
  context stage to read docs linked from tickets.
  Use when asked to "read this doc", "fetch this google doc", or "/fetch-doc <url>".
allowed-tools:
  - Bash
  - Read
triggers:
  - read this doc
  - fetch this google doc
---

## Usage

```bash
bash ~/.claude/skills/fetch-doc/scripts/fetch-doc.sh "<url>"
```

Output is the document's plain text (Sheets → CSV of the linked tab). Exit codes: `0` ok · `2` cookies expired/rejected · `3` auth needed, no cookie file yet · `4` HTTP/network failure. On `2`/`3`, relay the one-time setup below to the user, record the doc as unread (`contextGaps` when inside /work-ticket), and continue — never block on it.

Long documents: write the output to a file and Read selectively rather than dumping it all into context.

## One-time setup (auth-walled Google docs)

Anonymous export already works for "anyone with the link" docs — setup is only needed for restricted ones. The USER does this (same rule as project-init credentials — never ask them to hand over their Google password):

1. Install a cookies.txt exporter in the browser that's logged into Google (e.g. "Get cookies.txt LOCALLY" — exports Netscape format).
2. With a Google Doc open, export cookies for the current site (`docs.google.com` — include parent `.google.com` domain cookies if the extension offers it).
3. Save the file:

```bash
mkdir -p ~/.claude/secrets && chmod 700 ~/.claude/secrets
mv ~/Downloads/docs.google.com_cookies.txt ~/.claude/secrets/google-cookies.txt
chmod 600 ~/.claude/secrets/google-cookies.txt
```

4. Verify with one harmless read of a restricted doc the user names:

```bash
bash ~/.claude/skills/fetch-doc/scripts/fetch-doc.sh "<restricted-doc-url>" | head -5
```

Override the cookie file location with `FETCH_DOC_COOKIES=<path>` if needed.

## Hard rules

- Never print, cat, or copy the cookie file's contents anywhere — chat, logs, task artifacts, or other files. Reference it by path only.
- The cookie file lives in `~/.claude/secrets/` (user-level, since a Google session is account-wide, not per-project), mode 600. Never inside a repo.
- Google session cookies expire; on exit code 2 the fix is always "re-export", never debugging the cookie contents.
