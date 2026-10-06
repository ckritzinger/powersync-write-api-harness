# Write API test harness

Manual test harness for the [PowerSync reference write implementation](https://github.com/powersync-ja/powersync-reference-write-implementation) (the
"write API" below), per its `TestPlan.md` §7. Not automated: a real PowerSync client app for poking the write API against a
real database and a real hosted PowerSync instance, plus a read-only Rails app that shows what
actually landed in the database, independent of sync timing.

## Setup at a glance

Everything runs on your machine except two things: the **source database** (AWS RDS Postgres,
created by Terraform) and the **hosted PowerSync instance** (PowerSync Cloud, your account). This is
the whole path from nothing to a working harness; each step links to the detail further down.

### Prerequisites

- **AWS:** a named profile with rights to create an RDS instance and a small VPC
  (`export AWS_PROFILE=<name>`), and [Terraform](https://developer.hashicorp.com/terraform/install).
- **Tools:** Docker with Compose, Node 24 and pnpm 9, `jq`, and Ruby 3 for the `rake` tasks (use
  rbenv or asdf; macOS's built-in Ruby 2.6 is too old).
- **PowerSync Cloud:** an account and an instance to point at the database. Use a development
  instance: `rake connect` *replaces* its database connection, client auth keys and sync config.
  Install the CLI (`npm i -g powersync`) and run `powersync login`.
- **The write API:** a clone of [`powersync-reference-write-implementation`](https://github.com/powersync-ja/powersync-reference-write-implementation) next to this repo
  (`../powersync-reference-write-implementation`), at a version
  with the `.env.local` and `AUTH_*` supplement support described in [section 4](#4-write-api-under-test).

### Steps

1. **Create the database** (about 10 minutes for RDS). Details: [section 2](#2-source-database).
   ```bash
   cd infra
   cp terraform.tfvars.example terraform.tfvars     # set region; engine defaults to postgres
   terraform init && terraform apply
   ```
2. **Pick your PowerSync instance.** This writes `POWERSYNC_URL` into `backend/.env` and
   `frontend/.env`. Details: [section 3](#3-powersync-instance).
   ```bash
   cd ../powersync
   rake instance                       # lists your instances
   rake instance INSTANCE=<id>         # selects one
   ```
3. **Tell the Rails app which database to use** (`backend/.env`; the file already exists from step 2).
   ```bash
   cd ../backend
   echo "DATABASE_TYPE=postgres" >> .env
   echo "DATABASE_URI=$(terraform -chdir=../infra output -raw database_uri)" >> .env
   ```
4. **Create the tables and load the seed data** (6 lists and 25 todos across three test users).
   ```bash
   cd ../powersync && rake provision
   cd ../backend && docker compose run --rm backend bin/rails harness:seed
   ```
5. **Connect PowerSync to the database.** This creates the token signing key if it is missing,
   generates the config, shows a dry run and asks before deploying; the first deploy provisions the
   instance and takes a few minutes. Then check that replication has finished.
   ```bash
   cd ../powersync
   SKIP_PROVISION=1 rake connect       # step 4 already provisioned
   rake status                         # expect: connected, "Initial replication done: true"
   ```
6. **Start the Rails app.** It shows the database contents (the oracle) and issues every token.
   ```bash
   cd ../backend && docker compose up      # http://localhost:3000
   ```
7. **Configure and start the write API.** Details: [section 4](#4-write-api-under-test).
   ```bash
   cd ../powersync && rake write_api       # database, trusted key, token issuer/audience
   cd ../../powersync-reference-write-implementation && docker compose up --build      # http://localhost:6060
   ```
8. **Start the frontend.**
   ```bash
   cd ../write-api-harness/frontend
   pnpm install && pnpm dev                # http://localhost:5180
   ```
9. **Check it end to end** at http://localhost:5180:
   - The badge reaches `sync: connected` and Alice sees *Groceries*, *Work — Q3 launch* and *Empty
     list*. Bob and Carol, from the dropdown, see different lists: that is the per-user sync scoping.
   - Tick a todo. It changes at once, the Queue tab empties within seconds, and the Rails page shows
     the new value (the write went through the write API into the database).
   - Optional: change a row directly in the database and watch it arrive in the browser.
10. **Tear it down when you are done,** or the database keeps billing. From this repo's root:
    ```bash
    AWS_PROFILE=<name> infra/scripts/teardown.sh
    (cd backend && docker compose down); (cd ../powersync-reference-write-implementation && docker compose down)
    ```

| Port | What |
| --- | --- |
| 3000 | Rails app: the oracle view, token issuer, public key (JWKS) |
| 5180 | Frontend (Vue app plus a small Express server) |
| 6060 | The write API under test |

**By hand, once:** AWS credentials, `powersync login`, choosing the instance, and starting the three
servers. Everything else is scripted. If something is off:

- **`retrying` or a `download error` badge:** hover it for the message. Usual causes: the instance was
  never deployed, a wrong `POWERSYNC_URL`, or the PowerSync config does not trust the current signing
  key (re-run `rake connect`).
- **`upload error` badge:** the write API is down or rejecting. Check its logs. A 401 usually means
  re-run `rake write_api` and restart it.
- **"Cannot start" page in the browser:** the Rails app is not running.

## What is in the repo

| Part | What it is | Runs |
| --- | --- | --- |
| [`frontend/`](frontend) | Vue 3 + PowerSync web SDK client running the reference connector (symlinked); a small Express server that forwards token requests to Rails and collects dead letters. Uploads go from the browser straight to the write API | Locally |
| [`backend/`](backend) | Rails app: read-only oracle over the source DB (ActiveRecord or Mongoid), schema provisioning and seed data, and the **token issuer** (signs the test JWTs, serves the public key, knows the test users) | Docker, locally |
| [`keys/`](keys) | The token signing keypair; **`keys/jwks.json` is the public key to copy** into PowerSync and the write API | Created on first use |
| [`write-api-overrides/`](write-api-overrides) | Drop-in `authorizer.ts` / `fatal-error-handler.ts` for the write API, env-switchable test behaviors | Inside powersync-reference-write-implementation |
| [`powersync/`](powersync) | Sync Streams config (SQL and MongoDB variants) and a Rakefile that selects the instance, connects it to the current database and configures the write API | Locally, against PowerSync Cloud |
| [`infra/`](infra) | Terraform: the source database only (RDS per engine, or MongoDB Atlas), and the teardown script | AWS / Atlas |

```
 Browser (Vue + PowerSync SDK, local SQLite)
   ├─ token ──────▶ frontend server (:5180) ──▶ Rails app (:3000, signs the tokens)
   ├─ uploads ────▶ write API under test (:6060) ──▶ source database
   └─ sync ◀────── hosted PowerSync instance ◀── replication ◀── source database
 Rails app ─── reads the source database directly (the oracle view)
 Write API ─── onDeadLetter ──▶ frontend server (:5180) /api/dead-letters
```

The sections below are the detail behind the steps above.

## Reference connector (symlinked)

`frontend/src/example-client` is a symlink to `powersync-reference-write-implementation/example-client/src` (default: the
sibling checkout `../powersync-reference-write-implementation`). The harness runs the **modular** `PowersyncConnector`
unmodified; `frontend/src/powersync/connector.ts` subclasses it and overrides only its protected
hooks (`getBatchingConfig`, `onFatalTransaction`, `onRetryableError`, `onTransportError`) to drive
them from the UI. Edits to the reference connector take effect on the next reload.

```bash
cd frontend
pnpm link-example /path/to/powersync-reference-write-implementation   # repoint the symlink at another checkout
```

The reference connector builds both its token URL (`/api/auth/token`) and its upload URL
(`/api/data`) from one setting, `VITE_BACKEND_URL`. The harness sets it to the **write API's own
URL** (`WRITE_API_URL`), so uploads go **straight from the browser to the write API**, a
cross-origin request that also exercises the write API's CORS handling. That would make the
connector fetch tokens from the write API's own demo endpoint, whose keys nobody trusts, so the
subclass overrides the connector's private `fetchAuthToken` (an own property at runtime, since
TypeScript will not allow a subclass override) to call `/api/auth/token` on the frontend's own
origin instead. The frontend server forwards that to the Rails app (`BACKEND_URL`, default
`localhost:3000`), which signs the token; the same fetch feeds the PowerSync sync connection. The
frontend needs the Rails app running and says so if not.

There is deliberately no proxy between the browser and the write API. An earlier version had one,
with a bad-token selector, a "lose next response" toggle and a request log; they were dropped in
favour of a direct, realistic path. Bad tokens are still easy to produce by hand (section 1).

## 1. Signing keys and auth

The **Rails app signs every token** (`backend/app/services/`: `TestUsers`, `SigningKey`,
`TokenIssuer`; `AuthController`):

| Endpoint (Rails, `:3000`) | |
| --- | --- |
| `GET /api/auth/token?user_id=user-alice[&mode=expired]` | `{ token, powersync_url, sub, mode }`; users are `user-alice`, `user-bob`, `user-carol` (viewer) |
| `GET /.well-known/jwks.json` (also `/api/auth/keys`) | the public key as a JWKS |
| `GET /api/users` | the test users and the token modes (for the frontend's user switcher) |

Unauthenticated, like the rest of that app: a local dev tool that hands a token to anyone naming a
test user. Claims: `iss` = `JWT_ISSUER` (default `write-api-harness`), `aud` = `JWT_AUDIENCE`
(default `POWERSYNC_URL`, which PowerSync always accepts), plus `role` and `name`; set them in
`backend/.env` (`.env.example` lists them).

**The signing key lives in [`keys/`](keys)**, created on first use (the first token request, or
explicitly `docker compose run --rm backend bin/rails keys:generate` in `backend/`, or `rake keys`
in `powersync/`):

- `keys/jwks.json` — the **public key as a JWKS. This is the file to copy** wherever a service must
  trust these tokens.
- `keys/signing-key.pem` — the private key. Gitignored; both files are, since they belong to your
  checkout. Delete them for a new key, then re-trust the new `jwks.json` everywhere below.

```bash
cd backend && cp .env.example .env      # DATABASE_*, POWERSYNC_URL, JWT_*  (Rails app and its tokens)
cd ../frontend && cp .env.example .env  # WRITE_API_URL, POWERSYNC_URL       (BACKEND_URL defaults to :3000)
```

Neither PowerSync nor the write API can reliably fetch a JWKS from your laptop, so the default is
**inline keys** copied from `keys/jwks.json`:

- **PowerSync instance:** `rake connect` in `powersync/` writes it into the instance's client auth
  via the CLI (section 3). By hand: paste `keys/jwks.json`'s keys as the instance's inline JWKS and
  accept the token audience.
- **Write API:** `rake write_api` (section 4) sets this up: a `backend/powersync-config.json` of
  `{ "config": { "client_auth": { "jwks": <keys/jwks.json> } } }` plus the expected issuer and
  audience as `AUTH_ISSUER` / `AUTH_AUDIENCE` environment variables. `bin/rails keys:generate` prints
  the same values if you would rather do it by hand.

Alternative for a write API on the same machine: point it at the running Rails app,
`jwksUriOverride: 'http://host.docker.internal:3000/.well-known/jwks.json'` plus
`allowInsecureHttpHosts: ['host.docker.internal']` (or `http://127.0.0.1:3000/...` with
`allowLocalHttp: true` outside Docker). Useful for TestPlan §2's JWKS fetch failure: stop the Rails
app and watch the write API return 401 once its key cache expires.

Bad-token cases (§2) need no setup: ask the Rails app for a broken variant and send it to the write
API with `curl`. Modes: `expired`, `not-yet-valid`, `wrong-issuer`, `wrong-audience`, `wrong-key`
(same `kid`, other key), `no-sub`, `symmetric-hs256`, `malformed`, `missing` (no token at all, so
nothing to send). Each should be rejected with a 401:

```bash
for mode in valid expired wrong-issuer wrong-audience wrong-key no-sub symmetric-hs256 malformed; do
  token=$(curl -s "localhost:3000/api/auth/token?user_id=user-alice&mode=$mode" | jq -r .token)
  printf '%-16s' "$mode"
  curl -s -o /dev/null -w '%{http_code}\n' -XPOST localhost:6060/api/data \
    -H 'content-type: application/json' -H "authorization: Bearer $token" \
    -d '{"transactions":[{"crud":[]}]}'
done
```

Only `valid` should return 200. The browser app only ever sends valid tokens; on a 401 the connector
clears its cached token and fetches a fresh one, as it would in an app.

Supabase / Clerk verifier scenarios are out of scope here (tested with real provider accounts).

## 2. Source database

Only the database runs in the cloud; the write API, the Rails app and the frontend all run on your machine.
Pick an engine and keep **three** places in lockstep: the write API's `DATABASE_TYPE`/`DATABASE_URI`,
the Rails app's same two variables, and the PowerSync instance's source connection.

### Create the database (Terraform)

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # engine, db_ingress_cidrs (your IP + PowerSync egress IPs)
terraform init && terraform apply
terraform output database_type                 # → DATABASE_TYPE
terraform output -raw database_uri             # → DATABASE_URI (write API, Rails app, PowerSync)
```

- One RDS instance for the selected `engine` (`postgres`, `mysql`, `sqlserver`; free-tier classes)
  in its own small VPC, with the replication settings PowerSync needs (Postgres logical
  replication; MySQL ROW binlog + GTID; SQL Server CDC comes from `rake mssql:enable_cdc` below).
- The instance is publicly addressable and its port is open to `0.0.0.0/0` by default
  (`db_ingress_cidrs`): throwaway databases with a random password, destroyed after every session.
  The local write API, Rails app and hosted PowerSync all connect to it. Narrow the list if a
  database will live longer.
- Switching engines: change `engine` and `terraform apply` (replaces the RDS instance), then
  provision the schema again below and repoint the write API and PowerSync.
- MongoDB: `engine = "none"` (no RDS), then `infra/atlas`, a separate root that needs Atlas API keys,
  with your IP and PowerSync's egress IPs in `access_cidrs`. Atlas clusters are replica sets, as the
  write API's Mongo transactions require.
- **Postgres TLS:** RDS Postgres 15+ forces TLS by default, but the write API's Postgres persister
  ignores `sslmode` in `DATABASE_URI`. The harness turns `rds.force_ssl` off
  (`postgres_force_ssl = false`), so credentials cross the internet unencrypted (still
  SG-restricted): use throwaway credentials. With `postgres_force_ssl = true`, the write API
  connects only if its environment sets `PGSSLMODE=no-verify`, which node-postgres reads. This gap
  in the write API is worth a TestPlan §1/§5 note.

### Tear everything down (after every session)

```bash
infra/scripts/teardown.sh                  # terraform destroy, then verify (asks once; --yes skips)
infra/scripts/teardown.sh --check          # verify only
infra/scripts/teardown.sh --region us-east-1   # limit the check (default: every enabled region)
```

1. `terraform destroy` for `infra/` and, if it has state, `infra/atlas` (its `project_id` is read
   back from state).
2. A **read-only** check of the account that does not trust Terraform state: anything named
   `write-api-harness*` or tagged `Project=write-api-harness` (`HARNESS_NAME` overrides) in every
   enabled region — RDS instances and clusters, manual snapshots, retained automated backups,
   subnet/parameter groups, VPCs, security groups, EC2 instances, Elastic IPs, ECR repos, IAM
   roles/profiles from the earlier EC2 design, anything else carrying the tag, and leftover
   Terraform state. It deletes nothing: it lists what it finds and exits non-zero.

Clean up anything it reports by hand (or re-run the destroy). The tagging API can list a resource
for a few minutes after deletion, so a lone "tagged resource" line right after a destroy may be stale.

A profile with no default region is fine (it lists regions from `us-east-1`). If any AWS query
fails (permissions, a region you cannot query) the script prints `CHECK FAILED` with the reason and
exits non-zero: it never reports "Clean" for an account it could not fully check. Exit codes: 0 clean,
1 leftovers or failed checks, 2 could not start (no credentials, regions unlistable).

The check covers every enabled region, about 13 AWS calls each, so it runs eight regions at a time
(`CHECK_JOBS=n` changes that) and prints a line as each one finishes: expect a minute or two, not
silence. To check only where the harness ran: `--region us-east-1`, which takes seconds.

### Provision the schema and run the Rails app (local Docker)

```bash
cd backend
cp .env.example .env      # DATABASE_TYPE + DATABASE_URI from terraform output (same as the write API)
docker compose build
# SQL engines: create tables (+ engine-specific replication setup)
docker compose run --rm backend bin/rails db:create db:migrate
docker compose run --rm backend bin/rails postgres:publication   # Postgres
docker compose run --rm backend bin/rails mssql:enable_cdc       # SQL Server
# MongoDB: collections + $jsonSchema validators
docker compose run --rm backend bin/rails mongo:setup
# Seed data (any engine): idempotent; harness:reset deletes ALL lists/todos first
docker compose run --rm backend bin/rails harness:seed
docker compose up         # http://localhost:3000
```

Seed data (`backend/lib/seed_data.rb`): 6 lists / 25 todos across the three test users. Alice:
*Groceries*, *Work — Q3 launch* (quotes, unicode/emoji, a very long title, a mid-point position),
*Empty list*; Bob: *Home repairs* (a negative position), *Weekend*; Carol (viewer): *Reading list*.
Mixed completed/open items, some edited (`updated_at` after `created_at`). IDs start with
`5eed0000-` so seeded rows are easy to spot. Rows are written directly to the database
(provisioning, like migrations) and reach clients through PowerSync replication.

Restart the write API after `mongo:setup`: it discovers validators at startup.
`bin/rails mongo:drop_validators` (then restart) exercises the `SCHEMA_MISMATCH` path.

A database in a local container works too, for write-API-only checks (writes, oracle, dead
letters), but a hosted PowerSync instance cannot replicate from it, so nothing syncs back.

Schema notes (`backend/db/migrate/`):

- `id`/`list_id`: `uuid` on Postgres, `varchar(36)` elsewhere; MongoDB uses the UUID string as `_id`.
- `todos.list_id` has a foreign key (cascade) on SQL engines: the "bad list_id" debug write fails
  there. MongoDB has no FK, so the same write succeeds and shows under **Orphaned todos**.
- `todos.title` is `NOT NULL` / validator-required: the "null title" debug write fails on every engine.
- Timestamps are sent as `2026-10-06T10:00:00.123+00:00`. MySQL rejects JavaScript's
  `toISOString()` `Z` suffix and the default mapper does no conversion — a real §1 finding.
  SQL Server columns are `datetimeoffset(3)` because `datetime2` does not parse offsets.

**Deviation from TestPlan §7:** the plan runs the Rails (read) app on EC2 and keeps RDS private to it.
Here only the database is in the cloud and everything else runs locally, so the database accepts
connections from your IP and PowerSync's egress IPs instead.

## 3. PowerSync instance

`powersync/Rakefile` points the hosted instance at whatever database `backend/.env` names, using the
[PowerSync CLI](https://docs.powersync.com/tools/cli). It runs on the host (the Rails app is in Docker
and cannot use your PowerSync login):

```bash
# once: install the CLI (npm i -g powersync), then `powersync login` (or export PS_ADMIN_TOKEN)
cd powersync
rake help         # what it does and what stays manual
rake instance     # list your PowerSync instances (CLI installed + logged in)
rake instance INSTANCE=<id>   # select one: sets POWERSYNC_URL in backend/.env and frontend/.env
rake connect      # provision DB -> pull live config -> generate -> `deploy --dry-run` -> confirm -> deploy -> status
rake plan         # everything except the deploy
rake generate     # only write cli/service.yaml + cli/sync-config.yaml (no PowerSync account needed)
rake provision    # tables + PowerSync prerequisites in the current DB (Docker); `connect` runs it first
rake keys         # create the token signing key if needed; print the public JWKS and where it goes
rake status       # connection / replication status
```

Inputs (environment variables override the files): `DATABASE_TYPE`/`DATABASE_URI`, `JWT_ISSUER` and
`JWT_AUDIENCE` (default `POWERSYNC_URL`) from `backend/.env`, because the Rails app signs the
tokens; `POWERSYNC_URL` from `frontend/.env` or `backend/.env` (the 24-hex instance id is its first
label; or set `INSTANCE_ID`); the public key from `keys/jwks.json`. `YES=1` skips the confirmation,
`SKIP_PROVISION=1` skips provisioning, `POWERSYNC_CLI="npx -y powersync@0.10.2"` overrides the CLI
(without it: `powersync` on the PATH, else `npx powersync`).

What it generates in `powersync/cli/` (gitignored, rewritten each run):

- `service.yaml`: one replication connection for the current engine; the **inline public key**
  from `keys/jwks.json` as client auth (plus `JWT_AUDIENCE` as an additional audience when it is
  not the instance URL). `name` and `region` are kept from the live instance (`pull instance`),
  since a region cannot change. The database password is never written down: the file says
  `secret: !env POWERSYNC_DATABASE_PASSWORD` and the task hands the value to the CLI in its
  environment.
- `sync-config.yaml`: a copy of `sync-streams.yaml`, or `sync-streams.mongodb.yaml` for MongoDB:
  [Sync Streams](https://docs.powersync.com/sync/streams/overview) (config edition 3, not the
  deprecated Sync Rules). One auto-subscribed stream, `user_data`: lists where
  `owner_id = auth.user_id()` (the token's `sub`), and the todos of those lists via
  `list_id IN (SELECT id FROM lists WHERE owner_id = auth.user_id())`, since `todos` has no
  owner column. Clients need no change: auto-subscribed streams sync by default.

Per-engine details, from the CLI's config schema:

- **Postgres:** PowerSync Cloud supports only verified TLS (`verify-full`/`verify-ca`, no plaintext),
  so for RDS the task downloads the region's CA bundle from AWS (cached in `powersync/.cache/`) and
  embeds it as `cacert`. This is independent of the write API's plaintext-only Postgres connection
  (see the TLS note above): RDS accepts both.
- **MySQL:** the schema has no TLS options; the CLI's connection validation is the test.
- **SQL Server:** `schema: dbo`, `trustServerCertificate: true`; CDC comes from `rake provision`.
- **MongoDB:** the URI keeps the user and the password travels as the secret; `post_images:
  auto_configure` needs the Atlas user's `dbAdmin`, which `infra/atlas` grants.

Still manual: `powersync login`; the `.env` files; creating the database first (PowerSync Cloud must
reach it, so a local container does not work); restarting the write API after a MongoDB switch (it
reads validators at startup); reloading the frontend (clear its site data if it looks stuck on the
previous database's rows). The task warns when the database host is not reachable from the internet
or differs from the write API's settings (its `.env`, overridden by `.env.local`, in `../powersync-reference-write-implementation` or `WRITE_API_DIR`; `rake write_api` fixes that).

Verification status: the generated `service.yaml` validates against the CLI's JSON schema for all
four engines, and on Postgres/RDS `deploy --dry-run`'s connection test passed against a real
instance. The CLI validates sync config server-side, and only for a provisioned instance, so the
dry run does not cover it; the Sync Streams files were checked locally with the sync-rules parser
bundled in the CLI (`SqlSyncRules.validate`), and the real check happens on the first `deploy`.
The MySQL, SQL Server and MongoDB connection settings have not been tried against a real instance.

## 4. Write API under test

Runs locally (Docker Compose) against the cloud database. One task configures the `powersync-reference-write-implementation`
checkout (default `../powersync-reference-write-implementation`, or `WRITE_API_DIR=...`) from the harness's current settings;
then you start it the normal way, in that checkout:

```bash
cd powersync          # or backend/: the same task works there
rake write_api        # database, trusted key, issuer/audience

cd ../../powersync-reference-write-implementation
docker compose up --build
```

`rake write_api` does three things:

1. **Database:** `DATABASE_TYPE`/`DATABASE_URI` from `backend/.env` go into `.env.local` in the write
   API checkout (mode 600), a **second, gitignored env file**. They deliberately do **not** go into
   its `.env`, which is **tracked in its repo**: a database password written there would be one
   blanket commit away from history. The task refuses to write the password unless git ignores
   `.env.local`, and warns if it finds a password in `.env`.

   That checkout's `docker-compose.yaml` loads `.env` then an optional `.env.local` (later wins) via
   `env_file`, so a plain `docker compose up` there works too, with no flags. `.env` keeps the shared
   defaults such as `BATCH_ON_FATAL_ERROR`; put `HARNESS_*` switches or overrides in `.env.local`. This
   needed small changes in that repo (`.gitignore`, `docker-compose.yaml`, a README note); the task
   checks for them and says what is missing. One behavioural change: a variable set in your shell no
   longer overrides `.env`; use `.env.local`.
2. **Trusted key:** `keys/jwks.json` becomes `backend/powersync-config.json` (gitignored there).
3. **Issuer and audience:** `AUTH_ISSUER` and `AUTH_AUDIENCE` in the same `.env.local`. The write
   API's verifier reads its supplements from `AUTH_*` environment variables (`supplementsFromEnv`,
   documented in its `backend/src/auth/SETUP.md`), so no tracked source file is edited. The task
   refuses a checkout that predates this.

It is safe to re-run, which you should after changing the database, the key or the instance; then
restart the write API (it reads its configuration at startup). Postgres on RDS needs forced TLS off
(the Terraform default), because the write API's Postgres connection cannot use TLS.

Test it by hand with a token from the Rails app (add `&mode=expired` and friends for broken tokens,
to try the write API's auth rejections):

```bash
TOKEN=$(curl -s 'localhost:3000/api/auth/token?user_id=user-alice' | jq -r .token)
curl -s -XPOST localhost:6060/api/data -H 'content-type: application/json' \
  -H "authorization: Bearer $TOKEN" -d '{"transactions":[{"crud":[]}]}'    # {"results":[{"status":"success"}]}
```

The harness's behaviour overrides are separate: apply them to the checkout once, then switch them
with environment variables.

```bash
write-api-overrides/apply.sh ../powersync-reference-write-implementation     # --revert to undo (.orig backups)
```

Override behaviors are environment variables, read per request (set them in
the write API checkout's `.env.local`):

| Variable | Values | Covers |
| --- | --- | --- |
| `HARNESS_AUTHZ` | `allow` (default), `owner`, `deny` | §3 default / allow / deny (per-row: foreign `owner_id`; per-user: `viewer` role) |
| `HARNESS_SENTINEL` | `on` (default), `off` | §6 client-directed: todo titled `__TRIGGER_CONFIRMATION__` → `USER_CONFIRMATION_REQUIRED` |
| `HARNESS_CLASSIFY` | `default`, `backend`, `client`, `throw`, `non-boolean` | §6 routing, classification failure → retryable, no dead letter |
| `HARNESS_DEAD_LETTER` | `post` (default), `throw`, `reject`, `hang`, `slow` | §6 handler failures don't block the response |
| `HARNESS_DEAD_LETTER_URL` | e.g. `http://host.docker.internal:5180/api/dead-letters` | Dead letters appear in the frontend's Dead letters tab |

`BATCH_ON_FATAL_ERROR` (`stop`/`skip`) stays the write API's own setting; restart after changing it.

## 5. Running the frontend

The Rails app (`docker compose up` in `backend/`, section 2) must be running: it issues the tokens
and supplies the user list.

```bash
cd frontend
pnpm dev          # http://localhost:5180 (Express + Vite middleware, one origin)
pnpm start        # builds, then serves the production bundle on http://localhost:5180
```

UI:

- **User** dropdown: switch identity (one local database per user; reloads the page).
- **Lists / Todos:** create, rename, delete lists; create, edit, toggle, delete todos;
  drag to reorder (single-column `position` PATCH, distinct from the toggle's `completed`+`updated_at`).
- **Sync badge `retrying`:** connect() is in effect but the sync stream is failing. The SDK still
  uploads queued writes in this state, so *Upload once* is only offered after Disconnect.
- **Local rows after a rejection:** a released or backend-rejected write stays in the local DB until
  sync replaces it with server state; without a working PowerSync connection it never goes away.
- **Disconnect / Upload once:** queue writes offline, then send one `uploadData()` call through
  the same connector — builds multi-transaction batches deterministically (set *Max transactions*).
- **Debug tab:** `onFatalTransaction` policy, batch limits, debug writes (bad `list_id`, sentinel
  title, null title, foreign owner, mixed multi-table transaction) and a sequence queue
  (`ok, bad-list, ok` …) for stop/skip/`not_attempted` within one request. The error-path writes
  behave as described only once the write API's overrides are applied (section 4).
- **Client fatals:** retained client-directed transactions, hook call counts, manual **Release**
  (next hook call returns `'complete'`).
- **Queue:** live `ps_crud` contents. **Upload log:** the connector's hook activity (fatal-transaction
  decisions, retries, transport errors); request and response bodies are in the browser's Network
  tab, since uploads go straight to the write API. **Dead letters:** entries POSTed by the write
  API's `onDeadLetter`, with duplicate counts per transaction.

The Rails app (the oracle) shows what actually landed in the DB, independent of sync timing.

## TestPlan coverage map

| TestPlan | How |
| --- | --- |
| §1 engines, schema mapping | Engine switch (Terraform `engine`), Rails oracle, timestamp/boolean/position shapes, `mongo:drop_validators` |
| §1 / §6 `BATCH_ON_FATAL_ERROR` | Sequence `ok, bad-list, ok` with max transactions ≥ 3, Upload once, compare `stop` vs `skip` |
| §2 auth | Inline JWKS / remote JWKS config, broken tokens via `?mode=` and `curl` (section 1), stop the Rails app for JWKS fetch failure, rotate by deleting `keys/*` (then re-trust the new `jwks.json`) |
| §3 authz | `HARNESS_AUTHZ`, "List owned by …" debug write, Carol (viewer) |
| §4 upload flow | Normal UI use; mixed transaction; Disconnect → edits → Connect |
| §6 backend-directed | Bad list_id / null title + Dead letters tab + `HARNESS_DEAD_LETTER` modes |
| §6 client-directed | Sentinel todo + Client fatals tab (retain blocks queue; Release → complete) |
| §6 classification failure | `HARNESS_CLASSIFY=throw` / `non-boolean` → retryable, no dead letter |
| §6 duplicates | Not covered: it needs the response dropped after the write API applied the batch, which the removed proxy could do |
| §6 replacement workflow | Sentinel todo retained → queue a corrective edit behind it (blocked) → Release → corrective write uploads |
| §6 malformed response | Not covered: the stock write API never returns one; it needs something in between to alter the response |
