# Write API test harness

Manual test harness for the
[PowerSync reference write implementation](https://github.com/powersync-ja/powersync-reference-write-implementation)
(the "write API" below), per its `TestPlan.md` §7. Not automated: a real PowerSync client app for
poking the write API against a real database and a real hosted PowerSync instance, plus a
read-only Rails app, the "oracle", that shows what actually landed in the database, independent of
sync timing.

## Setup at a glance

Everything runs on your machine except two things: the **source database** (AWS RDS Postgres,
created by Terraform) and the **hosted PowerSync instance** (PowerSync Cloud, your account). This is
the whole path from nothing to a working harness. `rake help`, run in `powersync/`, lists the
scripted tasks and what stays manual.

### Prerequisites

- **AWS:** a named profile with rights to create an RDS instance and a small VPC
  (`export AWS_PROFILE=<name>`), and [Terraform](https://developer.hashicorp.com/terraform/install).
- **Tools:** Docker with Compose, Node 24 and pnpm 9, `jq`, and Ruby 3 for the `rake` tasks (use
  rbenv or asdf; macOS's built-in Ruby 2.6 is too old).
- **PowerSync Cloud:** an account and an instance to point at the database. Use a development
  instance: `rake connect` *replaces* its database connection, client auth keys and sync config.
  Install the CLI (`npm i -g powersync`) and run `powersync login`.
- **The write API:** a clone of
  [`powersync-reference-write-implementation`](https://github.com/powersync-ja/powersync-reference-write-implementation)
  next to this repo (`../powersync-reference-write-implementation`), at a version where its Compose
  file loads an optional gitignored `.env.local` after `.env`, and its token verifier reads its
  issuer and audience from `AUTH_*` environment variables. `rake write_api` (step 8) checks this and
  says what is missing.
- **Free ports:** 3000, 5180 and 6060 (see [Ports](#ports)).

### Steps

Run every block from **this repo's root**; each one changes directory for itself, so you can resume
at any step. Steps 6, 7 and 8 each start a server that keeps running: give each its own terminal tab.
Only these are manual: AWS credentials, `powersync login`, choosing the instance, and starting those
three servers. Everything else is scripted.

**Always test reading before writing.** Steps 1–7 bring up and check only the read path (database →
PowerSync → the frontend, with the Rails app beside it) while the write API is not running at all. The
write API starts in step 8, so a read problem can never be blamed on it. Do not start it earlier.

1. **Create the database** (about 10 minutes for RDS). The Terraform config is in `infra/`.
   ```bash
   cp infra/terraform.tfvars.example infra/terraform.tfvars   # then edit it: set your region
   (cd infra && terraform init && terraform apply)            # engine defaults to postgres
   ```
2. **Pick your PowerSync instance.** This writes `POWERSYNC_URL` into `backend/.env` and
   `frontend/.env`, creating them. It needs the CLI logged in (see Prerequisites).
   ```bash
   (cd powersync && rake instance)                     # lists your instances
   (cd powersync && rake instance INSTANCE=<id>)       # selects one
   ```
3. **Tell the Rails app which database to use** (`backend/.env`, created in step 2).
   ```bash
   echo "DATABASE_TYPE=postgres" >> backend/.env
   echo "DATABASE_URI=$(terraform -chdir=infra output -raw database_uri)" >> backend/.env
   ```
4. **Create the tables and load the seed data** (6 lists and 25 todos across three test users).
   ```bash
   (cd powersync && rake provision)
   (cd backend && docker compose run --rm backend bin/rails harness:seed)
   ```
5. **Connect PowerSync to the database.** This creates the token signing key if it is missing,
   generates the config, shows a dry run and asks before deploying (answer `y`). The first deploy
   provisions the instance and takes a few minutes. Then check that replication has finished.
   ```bash
   (cd powersync && SKIP_PROVISION=1 rake connect)     # step 4 already provisioned
   (cd powersync && rake status)                       # expect: connected, "Initial replication done: true"
   ```
6. **Start the Rails app** (its own terminal tab). It shows the database contents (the oracle) and
   issues every token.
   ```bash
   (cd backend && docker compose up)                   # http://localhost:3000
   ```
7. **Start the frontend and test reading** (its own terminal tab). The write API is not running yet,
   so only look; do not edit anything.
   ```bash
   (cd frontend && pnpm install && pnpm dev)           # http://localhost:5180
   ```
   Check at http://localhost:5180:
   - The badge reaches `sync: connected`. Alice sees *Groceries*, *Work — Q3 launch* and *Empty
     list*; from the dropdown, Bob sees *Home repairs* and *Weekend*, and Carol sees *Reading list*.
     That is the per-user sync scoping.
   - What the browser shows matches the Rails page (http://localhost:3000), which reads the
     database directly.
   - Optional: change a row directly in the database and watch it arrive in the browser.

   Do not go on until reading is right. Any edit made now just queues locally and shows an `upload
   error` badge; that is expected until step 8, and the edit uploads once the write API is up.
8. **Configure and start the write API** (its own terminal tab). `rake write_api` edits the write API
   checkout's *gitignored* files only: it puts the database settings and the token issuer/audience
   in its `.env.local` (never in its committed `.env`, so the password cannot be committed) and the
   trusted public key in its `backend/powersync-config.json`. It is safe to re-run; restart the
   write API after changing the database, the key or the instance.
   ```bash
   (cd powersync && rake write_api)                    # database, trusted key, token issuer/audience
   (cd ../powersync-reference-write-implementation && docker compose up --build)   # http://localhost:6060
   ```
9. **Test writing.** Reload http://localhost:5180, then tick a todo. It changes at once, any `upload
   error` badge clears, the Queue tab empties within seconds, and the Rails page shows the new value:
   the write went through the write API into the database, and replication brought it back.
10. **Tear it down when you are done,** or the database keeps billing. The script runs
    `terraform destroy`, then checks the whole AWS account read-only for anything left over; add
    `--check` to only check, or `--region <name>` to check one region quickly.
    ```bash
    AWS_PROFILE=<name> infra/scripts/teardown.sh
    (cd backend && docker compose down)
    (cd ../powersync-reference-write-implementation && docker compose down)
    ```

## Ports

| Port | What |
| --- | --- |
| 3000 | Rails app: the oracle view, token issuer, public key (JWKS) |
| 5180 | Frontend (Vue app plus a small Express server) |
| 6060 | The write API under test |
| 3001 | Optional JWKS-only proxy for tunnelling (below) |

An old container still holding one of these (6060 is the usual one) stops the new one from starting;
`docker ps` shows what is listening.

## Optional: serve the JWKS through ngrok

To let a remote service fetch the signing key by URL, instead of using the inline copy that
`rake connect` and `rake write_api` write:

```bash
(cd backend && docker compose --profile tunnel up)   # adds a small Caddy proxy on :3001
ngrok http 3001                                      # key at https://<your-ngrok-domain>/.well-known/jwks.json
```

Tunnel **3001, not 3000**. The proxy forwards only `GET`/`HEAD /.well-known/jwks.json` to the Rails
app and answers 404 to everything else, while port 3000 also hands a valid token to anyone who names
a test user and shows every row in the database. Pointing PowerSync or the write API at the URL is
done by hand for such a test; the tasks keep writing the inline key. ngrok's free tier can put a
browser warning page in front of browser-like clients; server-to-server fetches are normally
unaffected.

## If something is off

- **`retrying` or a `download error` badge:** hover it for the message. Usual causes: the instance was
  never deployed, a wrong `POWERSYNC_URL`, or the PowerSync config does not trust the current signing
  key (re-run `rake connect`).
- **`upload error` badge:** expected while you are only testing reads (the write API is not running
  yet). Once it is, the write API is down or rejecting: check its logs. A 401 usually means re-run
  `rake write_api` and restart it.
- **"Cannot start" page in the browser:** the Rails app is not running.
- **The write API stops with a missing `DATABASE_URI`:** `rake write_api` was not run, or its Compose
  file lists `DATABASE_*` under `environment:`, which overrides `.env.local`. The task names the lines.
- **A `rake` task fails with a syntax or version error:** you are on macOS's built-in Ruby 2.6. Use
  rbenv or asdf's Ruby 3.

## What is in the repo

How the pieces connect:

```
 Browser (Vue + PowerSync SDK, local SQLite)
   ├─ token ──────▶ frontend server (:5180) ──▶ Rails app (:3000, signs the tokens)
   ├─ uploads ────▶ write API under test (:6060) ──▶ source database
   └─ sync ◀────── hosted PowerSync instance ◀── replication ◀── source database
 Rails app ─── reads the source database directly (the oracle view)
 Write API ─── onDeadLetter ──▶ frontend server (:5180) /api/dead-letters
```

| Part | What it is | Runs |
| --- | --- | --- |
| [`frontend/`](frontend) | Vue 3 + PowerSync web SDK client running the reference connector (symlinked); a small Express server that forwards token requests to Rails and collects dead letters. Uploads go from the browser straight to the write API | Locally |
| [`backend/`](backend) | Rails app: read-only oracle over the source DB (ActiveRecord or Mongoid), schema provisioning and seed data, and the **token issuer** (signs the test JWTs, serves the public key, knows the test users) | Docker, locally |
| [`keys/`](keys) | The token signing keypair; **`keys/jwks.json` is the public key to copy** into PowerSync and the write API | Created on first use |
| [`powersync/`](powersync) | Sync Streams config (SQL and MongoDB variants) and a Rakefile that selects the instance, connects it to the current database and configures the write API | Locally, against PowerSync Cloud |
| [`infra/`](infra) | Terraform: the source database only (RDS per engine, or MongoDB Atlas), and the teardown script | AWS / Atlas |