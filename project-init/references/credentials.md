# Scoped-credential recipes

One per platform. Pattern: print the recipe → the USER runs the privileged part → you store only the scoped result in `.claude/secrets/` (600) → verify with one harmless read. Never accept the user's own admin credential for storage.

## Postgres — read-only role

Have the user run (as a superuser, against each database Claude should read):

```sql
CREATE ROLE claude_ro LOGIN PASSWORD '<generate: openssl rand -base64 24>';
GRANT CONNECT ON DATABASE <db> TO claude_ro;
\c <db>
GRANT USAGE ON SCHEMA public TO claude_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO claude_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO claude_ro;
```

Then write `.claude/secrets/pgpass` (`chmod 600`):

```
<host>:<port>:*:claude_ro:<password>
```

Verify: `PGPASSFILE=.claude/secrets/pgpass psql -h <host> -p <port> -U claude_ro -d <db> -c "SELECT 1;"`

## MySQL — read-only user

```sql
CREATE USER 'claude_ro'@'%' IDENTIFIED BY '<generated>';
GRANT SELECT ON <db>.* TO 'claude_ro'@'%';
```

`.claude/secrets/my.cnf` (`chmod 600`):

```ini
[client]
user=claude_ro
password=<password>
```

Verify: `mysql --defaults-extra-file=.claude/secrets/my.cnf -h <host> -e "SELECT 1;"`

## GitLab — project access token

User creates (Project → Settings → Access tokens): role **Developer**, scope **api** (required for MR create/update — there is no finer write scope; residual risk is mitigated by the deny rules + skill guardrails). Expiry ≤ 1 year.

Storage: if `glab` is already authenticated with the user's own token and they prefer to keep using it, accept that (guardrails still apply) but note it in `tracker.auth.method = "glab-config-user"`. For the dedicated token: `glab auth login --hostname gitlab.com --token <token>` or store as `GITLAB_TOKEN` in `.claude/secrets/env`.

Verify: `glab auth status` and one GET, e.g. `glab api projects/<repoProject-encoded> | head -c 200`.

## GitHub — fine-grained PAT

Repository access: only the project repos. Permissions: Contents RW, Pull requests RW, Issues RW, Metadata R. Nothing else (no Actions, no Administration).

Store via `gh auth login --with-token` under a dedicated config, or `GH_TOKEN` in `.claude/secrets/env`.

Verify: `gh auth status`, `gh repo view <repoProject>`.

## Jira — API token

User creates an API token for a service account (or their account if no service account). Scope: Jira read + comment. Configure the `jira` CLI config file under `.claude/secrets/`.

Verify: `jira issue list --plain | head -5`.

## AWS — read-only profile

User creates IAM user `claude-readonly` with managed policy `ReadOnlyAccess` (or a tighter project policy), generates an access key, then:

```bash
aws configure --profile claude-readonly   # user runs this; keys land in ~/.aws/credentials
```

Record only the profile NAME in `project.json` (`cloud.profile`). Verify: `aws --profile claude-readonly sts get-caller-identity`.

## GCP — viewer service account

```bash
gcloud iam service-accounts create claude-readonly
gcloud projects add-iam-policy-binding <project> --member=serviceAccount:... --role=roles/viewer
gcloud iam service-accounts keys create .claude/secrets/gcp-key.json --iam-account=...
gcloud config configurations create claude-readonly && gcloud auth activate-service-account --key-file=.claude/secrets/gcp-key.json
```

Record the configuration name. Verify: `gcloud --configuration claude-readonly projects list --limit 1`.

## `.claude/secrets/env`

Generic fallback for anything else, one `KEY=value` per line, `chmod 600`. Skills source it explicitly per command — it is never auto-loaded into the session.
