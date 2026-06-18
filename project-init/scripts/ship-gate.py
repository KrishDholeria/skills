#!/usr/bin/env python3
"""PreToolUse ship gate for the /work-ticket pipeline.

Blocks `glab mr create` / `gh pr create` (exit 2, reason on stderr) while the
current branch belongs to an active work-ticket task whose state.json lacks
spec.approved=true or verify.testsPassed=true. Plain `git push` is not gated —
WIP backups stay possible; the deliverable (the MR/PR) is what's enforced.

Branches with no matching task state are never touched, so the hook is inert
outside the pipeline.

Task state lives next to project.json: <git root>/.claude/tasks/<id>/state.json,
or one directory above the git root in workspace layouts.

Wired per-project by /project-init Phase 4 into <root>/.claude/settings.local.json
(templates/hooks.json). Stable path: ~/.claude/skills/project-init/scripts/ship-gate.py
"""
import json
import os
import re
import subprocess
import sys

MR_CREATE_RE = re.compile(r"\bglab\s+mr\s+create\b|\bgh\s+pr\s+create\b")


def git(args, cwd):
    try:
        out = subprocess.run(
            ["git", "-C", cwd] + args, capture_output=True, text=True, timeout=5
        )
        return out.stdout.strip()
    except Exception:
        return ""


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    cmd = (payload.get("tool_input") or {}).get("command", "")
    if not MR_CREATE_RE.search(cmd):
        return 0

    cwd = payload.get("cwd") or os.getcwd()
    root = git(["rev-parse", "--show-toplevel"], cwd)
    if not root:
        return 0
    branch = git(["branch", "--show-current"], root)
    if not branch:
        return 0

    candidates = [
        os.path.join(root, ".claude", "tasks"),
        os.path.join(os.path.dirname(root), ".claude", "tasks"),
    ]
    for tasks_dir in candidates:
        if not os.path.isdir(tasks_dir):
            continue
        for tid in sorted(os.listdir(tasks_dir)):
            state_file = os.path.join(tasks_dir, tid, "state.json")
            if not os.path.isfile(state_file):
                continue
            try:
                with open(state_file) as f:
                    state = json.load(f)
            except Exception:
                continue
            if state.get("stage") == "done" or state.get("branch") != branch:
                continue

            problems = []
            if not (state.get("spec") or {}).get("approved"):
                problems.append("spec is not approved (spec.approved=false)")
            if not (state.get("verify") or {}).get("testsPassed"):
                problems.append("tests are not passing (verify.testsPassed=false)")
            if problems:
                sys.stderr.write(
                    f"work-ticket ship gate: branch '{branch}' belongs to task {tid}, "
                    f"but {' and '.join(problems)}. Complete the missing /work-ticket "
                    f"stage(s) and update {state_file}, then retry.\n"
                )
                return 2
            return 0  # matching active task, all gates green
    return 0


if __name__ == "__main__":
    sys.exit(main())
