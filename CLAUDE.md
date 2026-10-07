# CLAUDE.md

Manual test harness for the PowerSync reference write implementation (`../powersync-reference-write-implementation`,
called "the write API"). `README.md` is the quick start; this file is what you need to change things safely.

## Test order: read first, then write

The user always sets up and verifies the **read path in isolation, before the write API is running at all**. Whenever you
write or change instructions (README steps, task output, runbooks, answers about setup), keep this order:
database → PowerSync connected (`rake connect`) → Rails app → frontend → **confirm reads** (`sync: connected`, each
user's lists, matching the Rails oracle) → only then configure and start the write API (`rake write_api`, then
`docker compose up` in its repo) → confirm writes. Never put the write API before the frontend and the Rails app, never
start it "to be ready", and never debug a read problem by involving it. In the read-only phase an `upload error` badge is
expected: edits queue locally and upload once the write API starts.

## Layout

| Dir | What | Runs |
| --- | --- | --- |
| `frontend/` | Vue 3 + PowerSync web SDK client, plus a small Express server (token proxy, dead-letter sink). pnpm | host, `:5180` |
| `backend/` | Rails app in Docker: read-only "oracle" view of the source DB, schema provisioning, seed data, **token issuer** (`app/services/`) | Docker, `:3000` |
| `powersync/` | `Rakefile` (stdlib-only Ruby 3, runs on the host) + `sync-streams*.yaml` | host |
| `infra/` | Terraform: the source database only (RDS or Atlas) and `scripts/teardown.sh` | AWS |
| `keys/` | Token signing keypair, created on first use. Contents are gitignored | n/a |

The write API runs on `:6060` from its own repo. Everything except the database and the hosted PowerSync
instance runs locally.

## Checks (run these after a change)

```bash
frontend/node_modules/.bin/vue-tsc --noEmit -p frontend/tsconfig.json     # or: pnpm check in frontend/
frontend/node_modules/.bin/tsc --noEmit -p frontend/tsconfig.server.json
ruby -c powersync/Rakefile; ruby -c backend/Rakefile
terraform -chdir=infra fmt -check -recursive && terraform -chdir=infra validate
bash -n infra/scripts/teardown.sh
```

There is no automated test suite. Verify Rails changes by building the image
(`docker build backend`) and running a task or request in it; the backend gems only exist in Docker.

## Design decisions (do not undo without asking)

- **Uploads go straight from the browser to the write API.** There is deliberately no proxy; an earlier
  one (bad-token selector, lose-response toggle, request log) was removed. `VITE_BACKEND_URL` is the
  write API's URL, set by `frontend/server/index.ts`.
- **The reference connector is symlinked, not copied:** `frontend/src/example-client` points at the write
  API repo's `example-client/src`. `frontend/src/powersync/connector.ts` subclasses it and overrides the
  *private* `fetchAuthToken` as an own property (TypeScript forbids a normal override) so tokens come from Rails.
- **Rails signs every token** (`TestUsers`, `SigningKey`, `TokenIssuer`). `TestUsers` is the single
  source of users (token subjects, frontend dropdown, seed owners). `?mode=` on `/api/auth/token` makes
  deliberately broken tokens for curl testing; the browser app only ever sends valid ones.
- **Never tunnel the Rails app (`:3000`) with ngrok.** It hands a valid token to anyone naming a test user and shows every
  row. The opt-in `jwks-proxy` Compose service (`--profile tunnel`, `backend/jwks-proxy.Caddyfile`) forwards only
  `GET`/`HEAD /.well-known/jwks.json` and 404s the rest; tunnel its port `3001`. Keep it deny-by-default.
- **Sync Streams (config edition 3), not Sync Rules.** One auto-subscribed stream, scoped by `auth.user_id()`.
- **Postgres TLS:** PowerSync Cloud requires verified TLS (the Rakefile embeds the RDS CA bundle), but the
  write API's Postgres connection cannot use TLS, so Terraform turns `rds.force_ssl` off. Throwaway databases only.
- **No error-path overrides ship with the harness.** The sentinel todo and foreign-owner write only fail if
  the write API itself is set up to reject them (TestPlan §7).

## Secrets and the write API repo

- The write API repo's root `.env` is **tracked** there. Never write a database password into it. `rake write_api`
  writes to its **gitignored** `.env.local` (and `backend/powersync-config.json`) and refuses if git would not ignore it.
- That repo's Compose file must not list `DATABASE_*`, `BATCH_ON_FATAL_ERROR` or `AUTH_*` under `environment:`:
  `environment:` overrides `env_file`, so `.env.local` would be silently ignored. `rake write_api` checks this.
- Its verifier reads issuer/audience from `AUTH_*` variables; never edit its source for per-machine settings.
- Never print or commit passwords, `keys/*`, `powersync/cli/`, `powersync/.cache/`, `.env`, Terraform state or
  `terraform.tfvars`. Mask URIs (`s#://[^:]+:[^@]*@#://***:***@#`). Do not commit real AWS account ids, RDS hosts or
  PowerSync instance ids into docs or examples.
- Test tasks against a scratch copy of the write API repo with a fake password, not the real `.env.local`.

## Running things

- `rake` tasks live in `powersync/Rakefile` and also work from `backend/` (its Rakefile forwards them before Rails
  loads, because the gems are not installed on the host). They need Ruby 3: macOS's 2.6 gives a clear error.
- `docker compose` runs one-off Rails tasks: `(cd backend && docker compose run --rm backend bin/rails <task>)`.
- Ports 3000, 5180, 6060 must be free. Compose names its project after the directory, so a renamed checkout
  leaves an old container holding 6060.
- Do not run PowerSync CLI, Terraform apply/destroy or AWS commands against the real accounts unless asked.
  The user runs those; show the commands.

## AWS cost and teardown

The database bills until `infra/scripts/teardown.sh` runs (`AWS_PROFILE` must be exported; the script also copes with
a profile that has no default region, falling back to `us-east-1`). It runs `terraform destroy`, then a **read-only** account-wide check that never deletes: the user chose that
over a deleting sweep, so do not add deletion. A failed AWS query must never produce a "Clean" verdict. Keep it
compatible with bash 3.2 (macOS), and remember the interactive shell is zsh: unquoted variables are not word-split, and a
variable named `path` is tied to `PATH` (name loop variables something else, or commands vanish).

## Known engine behaviours

MySQL rejects JavaScript's `...Z` timestamps and the write API's default mapper does no conversion, so the client sends
`+00:00`. SQL Server columns are `datetimeoffset(3)`. MongoDB has no foreign keys (a bad `list_id` succeeds) and
needs `$jsonSchema` validators (`rake mongo:setup`). Only Postgres/RDS has been exercised against a real
PowerSync instance; MySQL, SQL Server and MongoDB settings are unverified.

## Conventions

- Keep `README.md` a short quick start; put detail in code comments and `rake help`. The user cut a long README on purpose.
- Match existing style and comment density. Plain stdlib in the Rakefile (no gems).
- Prefer small, verified changes; say plainly what was and was not tested.
