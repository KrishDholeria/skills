#!/usr/bin/env bash
# Shared Step-0 for the work-ticket skill suite (create-spec, implement, ...).
# Resolves the project config and the task dir for a given task/ticket id,
# creating the task dir if it does not exist. understand-task does NOT use this
# (it owns task-dir creation inline); everything downstream sources this so the
# config-resolution + task-dir logic lives in exactly one place.
#
# Usage:   eval "$(bash <this>/task-env.sh <task-id>)"
# Emits:   CFG=<abs path to project.json>
#          TASK_DIR=<abs path to .claude/tasks/<task-id>>
# Exits non-zero (and prints ERROR: ... on stderr) if no project.json is found.
set -euo pipefail

TASK_ID="${1:?usage: task-env.sh <task-id>}"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CFG=""
for c in "$ROOT/.claude/project.json" "$(dirname "$ROOT")/.claude/project.json"; do
  [ -f "$c" ] && CFG="$c" && break
done

if [ -z "$CFG" ]; then
  echo "ERROR: No .claude/project.json found — run /project-init first." >&2
  exit 1
fi

TASK_DIR="$(dirname "$(dirname "$CFG")")/.claude/tasks/$TASK_ID"
mkdir -p "$TASK_DIR"

echo "CFG=$CFG"
echo "TASK_DIR=$TASK_DIR"
