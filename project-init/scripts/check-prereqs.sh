#!/usr/bin/env bash
# Preflight dependency check for /project-init. Read-only — never installs anything.
# Emits one line per dependency: STATUS|name|scope|found|install_hint
#   STATUS: OK | MISSING
#   scope:  required | <integration> (tracker-gitlab, db-postgres, ...) | optional
#
# Usage: check-prereqs.sh
set -uo pipefail

check() { # name scope cmd hint
  local name="$1" scope="$2" cmd="$3" hint="$4" found=""
  if found="$(command -v "$cmd" 2>/dev/null)"; then
    echo "OK|$name|$scope|$found|$hint"
  else
    echo "MISSING|$name|$scope||$hint"
  fi
}

# --- required: the bootstrap itself cannot run without these ---------------
check git      required git     "sudo apt install git"
check python3  required python3 "sudo apt install python3"

# --- conditional: needed only when the matching integration is enabled -----
check glab  tracker-gitlab glab "https://gitlab.com/gitlab-org/cli#installation (or: sudo apt install glab)"
check gh    tracker-github gh   "https://github.com/cli/cli#installation"
check jira  tracker-jira   jira "https://github.com/ankitpokhrel/jira-cli#installation"
check psql  db-postgres    psql "sudo apt install postgresql-client"
check mysql db-mysql       mysql "sudo apt install mysql-client"

# --- optional: bootstrap proceeds in degraded mode without these -----------
# node/npx -> GitNexus indexing + npm-based project commands
check node optional node "https://github.com/nvm-sh/nvm (recommended) or: sudo apt install nodejs npm"
check npx  optional npx  "comes with npm"

# GitNexus itself is fetched on demand by npx — only worth flagging if node exists
if command -v npx >/dev/null 2>&1; then
  if command -v gitnexus >/dev/null 2>&1 || [ -d "$HOME/.gitnexus" ]; then
    echo "OK|gitnexus|optional|npx gitnexus|auto-fetched by npx on first use"
  else
    echo "OK|gitnexus|optional|(will be fetched by npx on first use)|npm i -g gitnexus to pin it"
  fi
else
  echo "MISSING|gitnexus|optional||needs node/npx first"
fi

# Obsidian desktop app — vault works in plain-filesystem mode without it
if command -v obsidian >/dev/null 2>&1 || ls "$HOME"/.config/obsidian >/dev/null 2>&1 \
   || ls /usr/bin/obsidian /opt/Obsidian* /snap/bin/obsidian 2>/dev/null | head -1 >/dev/null; then
  echo "OK|obsidian-app|optional|installed|https://obsidian.md/download"
else
  echo "MISSING|obsidian-app|optional||https://obsidian.md/download — vault still works as plain markdown without it"
fi

# obsidian-claude-kb — detected by its INSTALLED artifacts (its install.sh puts
# scripts in ~/.claude/scripts/ and slash commands in ~/.claude/commands/),
# never by where the repo happens to be cloned.
KB_INSTALL_HINT="git clone https://github.com/KrishDholeria/obsidian-claude-kb.git && bash obsidian-claude-kb/install.sh (see repo README)"
if [ -f "$HOME/.claude/scripts/kb-save.sh" ] && [ -f "$HOME/.claude/commands/kb-init.md" ]; then
  echo "OK|obsidian-claude-kb|optional|installed (~/.claude/scripts, /kb-init)|$KB_INSTALL_HINT"
else
  echo "MISSING|obsidian-claude-kb|optional||$KB_INSTALL_HINT — without it, /project-init scaffolds a minimal vault inline and writes runbook notes directly"
fi
