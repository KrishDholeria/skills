#!/usr/bin/env bash
# Idempotently append local-only Claude entries to .git/info/exclude,
# guarded by marker comments so re-runs replace rather than duplicate.
#
# Usage: exclude-local.sh [project-root]
set -euo pipefail

ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/git-exclude.txt"

GIT_DIR="$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null || true)"
if [[ -z "$GIT_DIR" ]]; then
  echo "WARN: $ROOT is not a git repository — skipping .git/info/exclude setup." >&2
  exit 0
fi
[[ "$GIT_DIR" != /* ]] && GIT_DIR="$ROOT/$GIT_DIR"

EXCLUDE_FILE="$GIT_DIR/info/exclude"
mkdir -p "$(dirname "$EXCLUDE_FILE")"
touch "$EXCLUDE_FILE"

BEGIN='# >>> claude-code local-only (managed by /project-init) >>>'
END='# <<< claude-code local-only <<<'

# remove any existing managed block, then append the fresh one
TMP="$(mktemp)"
awk -v b="$BEGIN" -v e="$END" '
  $0 == b {skip=1; next}
  $0 == e {skip=0; next}
  !skip {print}
' "$EXCLUDE_FILE" > "$TMP"

{
  cat "$TMP"
  echo "$BEGIN"
  cat "$TEMPLATE"
  echo "$END"
} > "$EXCLUDE_FILE"
rm -f "$TMP"

echo "updated: $EXCLUDE_FILE"
