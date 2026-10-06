# Signing key for the test tokens

The Rails app (`backend/`) signs every test JWT with an RS256 keypair kept in this folder. It is
created the first time it is needed (the first token request, or `docker compose run --rm backend
bin/rails keys:generate` from `backend/`, or `rake keys` from `powersync/`).

| File | What | Share it? |
| --- | --- | --- |
| `jwks.json` | The **public** key as a JWKS. **Copy this** into the PowerSync instance's client auth and the write API's verifier. | Yes |
| `signing-key.pem` | The private key. | No. Gitignored. |

Both are gitignored: they belong to your checkout, and PowerSync and the write API must trust the
key you actually run. Deleting them makes a new key on the next request; then PowerSync and the
write API must be given the new `jwks.json` (`rake connect` in `powersync/` does the PowerSync side).

Where the public key goes:

- **PowerSync instance:** `rake connect` in `powersync/` writes it into the instance's `client_auth`
  config via the PowerSync CLI. By hand: paste the contents of `jwks.json` as the instance's inline
  JWKS keys.
- **Write API:** a `backend/powersync-config.json` containing
  `{ "config": { "client_auth": { "jwks": <contents of jwks.json> } } }` plus the issuer/audience
  expected issuer and audience as `AUTH_ISSUER` / `AUTH_AUDIENCE` environment variables (`rake
  write_api` sets all of it; `bin/rails keys:generate` prints it), or point `AUTH_JWKS_URI_OVERRIDE` at
  the running Rails app: `http://host.docker.internal:3000/.well-known/jwks.json`.

The issuer and audience in the tokens come from `JWT_ISSUER` and `JWT_AUDIENCE` in `backend/.env`
(audience defaults to `POWERSYNC_URL`).
