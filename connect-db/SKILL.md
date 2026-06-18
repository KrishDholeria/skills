---
name: connect-db
version: 2.0.0
description: |
  Read-only access to the project's database. Lists databases/tables, inspects
  schema, or runs SELECT queries. Engine, host, and the scoped read-only
  credential come from .claude/project.json. Refuses any write/DDL operation.
  Arguments: [db_name] [sql_query | describe table_name]
allowed-tools:
  - Bash
---

Query the project database in read-only mode. Only SELECT statements are permitted.

## Step 0 — Resolve project config

Read `.claude/project.json` (git root, or one directory above for workspaces): `database.engine`, `database.host`, `database.port`, `database.user`, `database.credentialFile`, `database.databases`.

**There are NO default credentials.** If config or credential file is missing, say:
> "No database configured for this project — run `/project-init` to create a scoped read-only user, or give me host/user/credential-file to use for this session."

Never assume a password, never accept a password inline in chat for storage — if the user pastes one, use it for the session via the credential-file mechanism below and recommend rotating it into `/project-init`'s flow.

The credential file path is relative to the project root: e.g. `.claude/secrets/pgpass` (postgres, `chmod 600`, format `host:port:db:user:password`) or `.claude/secrets/my.cnf` (mysql).

## Arguments

`$ARGUMENTS` — `[db_name] [sql_query | describe <table_name>]`

| Arguments | Mode |
|-----------|------|
| (none) | List all databases |
| `<db_name>` | List tables in that database |
| `<db_name> describe <table>` | Describe table schema |
| `<db_name> <SELECT ...>` | Run SELECT query |

## engine = postgres

Always invoke as (credential only via PGPASSFILE — never `PGPASSWORD`, never a CLI flag):

```bash
PGPASSFILE="<root>/.claude/secrets/pgpass" psql -h "<host>" -p "<port>" -U "<user>" [options]
```

- List databases: `... -c "\l"`
- List tables: `... -d "$DB_NAME" -c "\dt public.*"` plus approximate row counts:
  `... -d "$DB_NAME" -t -A -c "SELECT schemaname||'.'||relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 40;"`
- Describe: `... -d "$DB_NAME" -c "\d+ $TABLE_NAME"`
- SELECT (after the safety check): `... -d "$DB_NAME" -c "BEGIN READ ONLY; $SQL; COMMIT;"`

`BEGIN READ ONLY` is a server-level safeguard; the scoped `claude_ro`-style role (SELECT-only grants) is the primary enforcement. If connection fails with "role does not exist" or auth error, point the user at the `/project-init` Phase 3 recipe to (re)create the read-only role.

## engine = mysql

```bash
mysql --defaults-extra-file="<root>/.claude/secrets/my.cnf" -h "<host>" -P "<port>" [options]
```

- List databases: `... -e "SHOW DATABASES;"`
- List tables: `... -D "$DB_NAME" -e "SHOW TABLES;"`
- Describe: `... -D "$DB_NAME" -e "SHOW CREATE TABLE \`$TABLE_NAME\`\G"`
- SELECT (after the safety check): `... -D "$DB_NAME" -e "SET SESSION TRANSACTION READ ONLY; START TRANSACTION; $SQL; COMMIT;"`

## SAFETY CHECK — always perform before executing any query

1. Strip leading whitespace and SQL comments (`--` and `/* */`).
2. Check the first keyword is `SELECT` (case-insensitive). (`WITH ... SELECT` CTEs are fine; verify the statement contains no data-modifying CTE.)
3. Scan the full query for these keywords at statement level (not inside string literals). If any found, **refuse and explain**:
   `INSERT`, `UPDATE`, `DELETE`, `DROP`, `CREATE`, `ALTER`, `TRUNCATE`,
   `GRANT`, `REVOKE`, `COPY`, `EXECUTE`, `CALL`, `DO`, `SET`, `LOCK`, `LOAD`, `OUTFILE`

## Output formatting

- Present results as a markdown table.
- \> 100 rows: show first 100 and note "Showing 100 of N rows — add `LIMIT` to see fewer."
- On error: show the full error message and suggest a fix.

## Security rules

- NEVER run non-SELECT queries.
- NEVER print credentials or credential-file contents in any output.
- NEVER pass a password as a CLI flag or env var visible in process args — only PGPASSFILE / --defaults-extra-file.
- Always wrap data queries in the engine's read-only transaction form.
