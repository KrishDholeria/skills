# .claude/secrets/ formats

Directory `chmod 700`, every file `chmod 600`. Never committed (covered by `.git/info/exclude`), never echoed to chat, never inlined in config or permission rules — config stores only these file paths.

| File | Used by | Format |
|---|---|---|
| `pgpass` | psql via `PGPASSFILE` | `host:port:db:user:password` (use `*` for db to cover all) |
| `my.cnf` | mysql via `--defaults-extra-file` | ini: `[client]\nuser=...\npassword=...` |
| `env` | anything else; sourced explicitly per command, never auto-loaded | `KEY=value` lines (e.g. `GITLAB_TOKEN=...`) |
| `gcp-key.json` | gcloud service-account auth | as produced by `gcloud iam service-accounts keys create` |
