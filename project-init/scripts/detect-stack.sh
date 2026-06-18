#!/usr/bin/env bash
# Read-only stack detection. Scans the project for stack signals and emits a
# JSON report on stdout. Never modifies anything.
#
# Usage: detect-stack.sh [project-root]
set -uo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT" || { echo '{"error": "root not found"}'; exit 1; }

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }

sha() { # sha256 of a file if it exists, else null
  if [[ -f "$1" ]]; then printf '"%s"' "$(sha256sum "$1" | cut -d' ' -f1)"; else printf 'null'; fi
}

# --- git ---------------------------------------------------------------
IS_GIT=False; REMOTE=""; DEFAULT_BRANCH=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=True
  REMOTE="$(git remote get-url origin 2>/dev/null || true)"
  DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  [[ -z "$DEFAULT_BRANCH" ]] && DEFAULT_BRANCH="$(git branch -l main master --format='%(refname:short)' 2>/dev/null | head -1)"
fi

# --- workspace layout: subdirs that are their own git repos ---------------
SUBREPOS=()
for d in */; do
  d="${d%/}"
  [[ -d "$d/.git" ]] || continue
  r="$(git -C "$d" remote get-url origin 2>/dev/null || true)"
  b="$(git -C "$d" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  SUBREPOS+=("{\"path\": \"$d\", \"remote\": $( [[ -n "$r" ]] && printf '"%s"' "$r" || echo null ), \"defaultBranch\": $( [[ -n "$b" ]] && printf '"%s"' "$b" || echo null )}")
done
# workspace root with no remote of its own: borrow tracker detection from the first sub-repo remote
if [[ -z "$REMOTE" && ${#SUBREPOS[@]} -gt 0 ]]; then
  REMOTE="$(git -C "$(echo "${SUBREPOS[0]}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])')" remote get-url origin 2>/dev/null || true)"
fi

# --- tracker from remote -------------------------------------------------
TRACKER="null"; TRACKER_CLI="null"; REPO_PROJECT="null"
case "$REMOTE" in
  *gitlab*) TRACKER='"gitlab"'; TRACKER_CLI='"glab"' ;;
  *github*) TRACKER='"github"'; TRACKER_CLI='"gh"' ;;
esac
if [[ -n "$REMOTE" ]]; then
  # strip protocol/host and .git suffix -> namespace/project
  RP="$(echo "$REMOTE" | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')"
  [[ -n "$RP" ]] && REPO_PROJECT="\"$RP\""
fi

# --- languages / runtimes / package managers ----------------------------
LANGS=(); PKG_MGRS=(); CANDIDATES=()
add_lang() { local l; for l in "${LANGS[@]:-}"; do [[ "$l" == "$1" ]] && return; done; LANGS+=("$1"); }

# find manifest files up to 2 levels deep, skipping vendor dirs
MANIFESTS="$(find . -maxdepth 3 \( -name node_modules -o -name .git -o -name venv -o -name .venv -o -name vendor \) -prune -o -type f \( \
  -name package.json -o -name requirements.txt -o -name pyproject.toml -o -name poetry.lock -o -name uv.lock \
  -o -name go.mod -o -name Cargo.toml -o -name Gemfile -o -name pom.xml -o -name build.gradle -o -name composer.json \
  -o -name Makefile -o -name manage.py \) -print 2>/dev/null)"

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  dir="$(dirname "$f" | sed 's|^\./||')"
  base="$(basename "$f")"
  case "$base" in
    package.json)
      add_lang javascript; PKG_MGRS+=("npm")
      for s in test lint build dev start; do
        cmd="$(python3 -c "import json;d=json.load(open('$f'));print('npm run $s' if '$s' in d.get('scripts',{}) else '')" 2>/dev/null)"
        [[ -n "$cmd" ]] && CANDIDATES+=("{\"kind\": \"$s\", \"cmd\": \"$cmd\", \"cwd\": \"$dir\", \"from\": \"$f\"}")
      done
      CANDIDATES+=("{\"kind\": \"install\", \"cmd\": \"npm install\", \"cwd\": \"$dir\", \"from\": \"$f\"}")
      ;;
    requirements.txt)
      add_lang python; PKG_MGRS+=("pip")
      CANDIDATES+=("{\"kind\": \"install\", \"cmd\": \"pip install -r $base\", \"cwd\": \"$dir\", \"from\": \"$f\"}")
      ;;
    pyproject.toml)
      add_lang python
      if grep -q 'tool.poetry' "$f" 2>/dev/null; then PKG_MGRS+=("poetry")
      elif [[ -f "$dir/uv.lock" ]]; then PKG_MGRS+=("uv"); fi
      grep -q 'pytest' "$f" 2>/dev/null && CANDIDATES+=("{\"kind\": \"test\", \"cmd\": \"pytest\", \"cwd\": \"$dir\", \"from\": \"$f\"}")
      grep -q 'ruff' "$f" 2>/dev/null && CANDIDATES+=("{\"kind\": \"lint\", \"cmd\": \"ruff check .\", \"cwd\": \"$dir\", \"from\": \"$f\"}")
      ;;
    manage.py)
      add_lang python
      CANDIDATES+=("{\"kind\": \"dev\", \"cmd\": \"python manage.py runserver\", \"cwd\": \"$dir\", \"from\": \"$f\"}")
      CANDIDATES+=("{\"kind\": \"test\", \"cmd\": \"python manage.py test\", \"cwd\": \"$dir\", \"from\": \"$f\"}")
      ;;
    go.mod) add_lang go; CANDIDATES+=("{\"kind\": \"test\", \"cmd\": \"go test ./...\", \"cwd\": \"$dir\", \"from\": \"$f\"}") ;;
    Cargo.toml) add_lang rust; CANDIDATES+=("{\"kind\": \"test\", \"cmd\": \"cargo test\", \"cwd\": \"$dir\", \"from\": \"$f\"}") ;;
    Gemfile) add_lang ruby; PKG_MGRS+=("bundler") ;;
    pom.xml|build.gradle) add_lang java ;;
    composer.json) add_lang php; PKG_MGRS+=("composer") ;;
  esac
done <<< "$MANIFESTS"

# --- database from docker-compose / .env ---------------------------------
DB_ENGINE="null"; DB_HOST="null"; DB_PORT="null"
COMPOSE_FILE="$(ls docker-compose*.y*ml compose*.y*ml 2>/dev/null | head -1)"
if [[ -n "${COMPOSE_FILE:-}" ]]; then
  if grep -qE 'image:.*postgres' "$COMPOSE_FILE"; then DB_ENGINE='"postgres"'; DB_HOST='"localhost"'; DB_PORT='5432'; fi
  if grep -qE 'image:.*(mysql|mariadb)' "$COMPOSE_FILE"; then DB_ENGINE='"mysql"'; DB_HOST='"localhost"'; DB_PORT='3306'; fi
fi
if [[ "$DB_ENGINE" == "null" ]]; then
  for envf in .env .env.example .env.local backend/.env backend/.env.example; do
    [[ -f "$envf" ]] || continue
    if grep -qE '^(DATABASE_URL=postgres|POSTGRES_)' "$envf" 2>/dev/null; then DB_ENGINE='"postgres"'; DB_HOST='"localhost"'; DB_PORT='5432'; break; fi
    if grep -qE '^(DATABASE_URL=mysql|MYSQL_)' "$envf" 2>/dev/null; then DB_ENGINE='"mysql"'; DB_HOST='"localhost"'; DB_PORT='3306'; break; fi
  done
fi

# --- cloud ----------------------------------------------------------------
CLOUD="null"
if [[ -d terraform ]] || ls *.tf >/dev/null 2>&1; then
  grep -rqlE 'provider\s+"aws"' --include='*.tf' . 2>/dev/null && CLOUD='"aws"'
  grep -rqlE 'provider\s+"google"' --include='*.tf' . 2>/dev/null && CLOUD='"gcp"'
fi
if [[ "$CLOUD" == "null" ]]; then
  grep -rqlE 'boto3|aws-sdk|@aws-sdk' --include='*.txt' --include='*.toml' --include='package.json' --exclude-dir=node_modules -m1 . 2>/dev/null && CLOUD='"aws"'
  grep -rqlE 'google-cloud-|@google-cloud' --include='*.txt' --include='*.toml' --include='package.json' --exclude-dir=node_modules -m1 . 2>/dev/null && CLOUD='"gcp"'
fi

# --- CI config -------------------------------------------------------------
CI_FILE=""
for c in .gitlab-ci.yml .github/workflows; do [[ -e "$c" ]] && CI_FILE="$c" && break; done

# --- fingerprints -----------------------------------------------------------
FP_LOCK="{}"
LOCKS="$(find . -maxdepth 3 \( -name node_modules -o -name .git \) -prune -o -type f \( -name package-lock.json -o -name poetry.lock -o -name uv.lock -o -name requirements.txt -o -name go.sum -o -name Cargo.lock \) -print 2>/dev/null)"
if [[ -n "$LOCKS" ]]; then
  FP_LOCK="$(while IFS= read -r f; do [[ -n "$f" ]] && printf '"%s": "%s",' "${f#./}" "$(sha256sum "$f" | cut -d' ' -f1)"; done <<< "$LOCKS")"
  FP_LOCK="{${FP_LOCK%,}}"
fi

# --- emit -------------------------------------------------------------------
# JSON-fragment values (already valid JSON: quoted strings, numbers, or null)
export D_ROOT="$ROOT" D_IS_GIT="$IS_GIT" D_REMOTE="$REMOTE" D_DEFAULT_BRANCH="$DEFAULT_BRANCH"
export D_TRACKER="$TRACKER" D_TRACKER_CLI="$TRACKER_CLI" D_REPO_PROJECT="$REPO_PROJECT"
export D_LANGS="${LANGS[*]:-}" D_PKG_MGRS="${PKG_MGRS[*]:-}"
export D_CANDIDATES="$( (IFS=$'\n'; echo "${CANDIDATES[*]:-}") )"
export D_DB_ENGINE="$DB_ENGINE" D_DB_HOST="$DB_HOST" D_DB_PORT="$DB_PORT" D_CLOUD="$CLOUD"
export D_CI_FILE="$CI_FILE" D_FP_LOCK="$FP_LOCK"
export D_SUBREPOS="$( (IFS=$'\n'; echo "${SUBREPOS[*]:-}") )"
export D_FP_COMPOSE="$(sha "${COMPOSE_FILE:-/nonexistent}")"
export D_FP_CI="$( [[ -n "$CI_FILE" && -f "$CI_FILE" ]] && sha "$CI_FILE" || echo null )"

python3 - <<'PYEOF'
import json, os, hashlib

def env(k): return os.environ.get(k, "")
def jfrag(k):  # parse a JSON-fragment env var ("null", '"postgres"', "5432")
    v = env(k).strip()
    return json.loads(v) if v else None

remote = env("D_REMOTE") or None
candidates = [json.loads(l) for l in env("D_CANDIDATES").splitlines() if l.strip()]

print(json.dumps({
    "root": env("D_ROOT"),
    "isGit": env("D_IS_GIT") == "True",
    "git": {"remote": remote, "defaultBranch": env("D_DEFAULT_BRANCH") or None},
    "subRepos": [json.loads(l) for l in env("D_SUBREPOS").splitlines() if l.strip()],
    "tracker": {"type": jfrag("D_TRACKER"), "cli": jfrag("D_TRACKER_CLI"), "repoProject": jfrag("D_REPO_PROJECT")},
    "languages": env("D_LANGS").split(),
    "packageManagers": sorted(set(env("D_PKG_MGRS").split())),
    "commandCandidates": candidates,
    "database": {"engine": jfrag("D_DB_ENGINE"), "host": jfrag("D_DB_HOST"), "port": jfrag("D_DB_PORT")},
    "cloud": {"provider": jfrag("D_CLOUD")},
    "ci": env("D_CI_FILE") or None,
    "fingerprints": {
        "gitRemote": hashlib.sha256(remote.encode()).hexdigest() if remote else None,
        "lockfiles": jfrag("D_FP_LOCK") or {},
        "dockerCompose": jfrag("D_FP_COMPOSE"),
        "ciConfig": jfrag("D_FP_CI"),
    },
}, indent=2))
PYEOF
