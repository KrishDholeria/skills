#!/usr/bin/env bash
# Compare a fresh detection run against an existing .claude/project.json.
# Emits a JSON drift report on stdout. Read-only.
#
# Usage: drift-diff.sh <project-root>
set -euo pipefail

ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$ROOT/.claude/project.json"

[[ -f "$CFG" ]] || { echo '{"error": "no project.json — run full bootstrap"}'; exit 1; }

DETECTION="$(bash "$SCRIPT_DIR/detect-stack.sh" "$ROOT")"

CFG_PATH="$CFG" DETECTION_JSON="$DETECTION" python3 - <<'PYEOF'
import json, os

det = json.loads(os.environ["DETECTION_JSON"])
cfg = json.load(open(os.environ["CFG_PATH"]))

drifts = []
declined = set(cfg.get("detection", {}).get("declined", []))
def drift(category, field, configured, detected, action):
    if configured == detected:
        return
    # detection blind spot: it cannot see what config knows (e.g. workspace root
    # without its own git repo, DB configured manually) — never propose removal
    if detected is None and configured is not None:
        return
    # user explicitly declined this integration — don't re-propose
    if field in declined:
        return
    drifts.append({"category": category, "field": field,
                   "configured": configured, "detected": detected,
                   "proposedAction": action})

fp_old = cfg.get("detection", {}).get("fingerprints", {})
fp_new = det.get("fingerprints", {})

drift("git", "git.remote", cfg.get("git", {}).get("remote"), det["git"]["remote"], "update remote + re-derive tracker")
drift("git", "git.defaultBranch", cfg.get("git", {}).get("defaultBranch"), det["git"]["defaultBranch"], "update if remote HEAD moved")
drift("tracker", "tracker.type", cfg.get("tracker", {}).get("type"), det["tracker"]["type"], "review tracker config + permission fragment")
drift("database", "database.engine", cfg.get("database", {}).get("engine"), det["database"]["engine"], "review db config + credentials + fragment")
drift("cloud", "cloud.provider", cfg.get("cloud", {}).get("provider"), det["cloud"]["provider"], "review cloud config + fragment")

# lockfile-level changes -> re-verify commands
lock_old, lock_new = fp_old.get("lockfiles", {}), fp_new.get("lockfiles", {})
for f in sorted(set(lock_old) | set(lock_new)):
    if lock_old.get(f) != lock_new.get(f):
        state = "new" if f not in lock_old else ("removed" if f not in lock_new else "changed")
        drifts.append({"category": "commands", "field": f"lockfile:{f}",
                       "configured": state != "new" and "present" or None,
                       "detected": state != "removed" and "present" or None,
                       "proposedAction": f"lockfile {state} — re-verify commands in that directory"})

for key, action in [("dockerCompose", "compose changed — re-check database detection"),
                    ("ciConfig", "CI config changed — re-check lint/test commands")]:
    if fp_old.get(key) != fp_new.get(key):
        drifts.append({"category": "infra", "field": f"fingerprint:{key}",
                       "configured": fp_old.get(key), "detected": fp_new.get(key),
                       "proposedAction": action})

# detected command candidates not present in config — only meaningful when some
# manifest actually changed; otherwise candidates the user already declined would
# re-surface as drift on every run
manifests_changed = any(d["category"] in ("commands", "infra") for d in drifts)
if manifests_changed:
    cfg_cmds = {v.get("cmd") for v in cfg.get("commands", {}).values() if isinstance(v, dict)}
    for c in det.get("commandCandidates", []):
        if c["cmd"] not in cfg_cmds:
            drifts.append({"category": "commands", "field": f"candidate:{c['kind']}",
                           "configured": None, "detected": f"{c['cmd']} (cwd: {c['cwd']})",
                           "proposedAction": "new command candidate — add?"})

print(json.dumps({"drift": drifts, "count": len(drifts),
                  "freshFingerprints": fp_new, "detection": det}, indent=2))
PYEOF
