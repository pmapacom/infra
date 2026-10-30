# env/db/external — provisioning the external Postgres

The stores are **not** in this repo any more: there are no Postgres or Redis
containers, no named volumes and no `<svc>-data` networks. Postgres lives on the
external server `80.66.64.227:5432`, and this folder is what prepares it.

**One shared login role — `pmapa_user` — and one database per service**, each
database named `pmapa_<svc>` and owned by `pmapa_user`:

    pmapa_auth   pmapa_user   pmapa_travel   pmapa_post   pmapa_store
    pmapa_stay   pmapa_message   pmapa_media   pmapa_notification

(The database named `pmapa_user` is the *user* service's database; the role is
also `pmapa_user`. Same name, different objects.) `stats` is not in the list —
its only store is the external managed Redis.

## Trust model — why one role, not nine

Every service runs on the **same machine**, and the database only accepts
connections from that machine's IP (a firewall allow-list on the Postgres side).
A password that leaks from one service leaks them all — they share a host — so
per-service roles would buy no real isolation. Hence **one** login role and
**one** password for all nine databases.

Separation is therefore **logical only**: each service still has its own
database (`pmapa_<svc>`), so a bug in one service cannot touch another's tables
by accident, and dumps/migrations/backups stay per-service. But on the database
side there is no access boundary between services any more — `pmapa_user` can
connect to all nine. `CONNECT` is still revoked from `PUBLIC` on every database,
which keeps *other* roles out; the real trust boundary is the firewall, not the
role.

## Files

| File | What it does |
|------|--------------|
| `provision.sh` | Driver — creates the `pmapa_user` role once, then loops over the nine services creating each `pmapa_<svc>` database. Idempotent. Prints ready-made `<SVC>_DATABASE_URL` lines for the root `.env`. |
| `database.sql` | One call: `CREATE ROLE pmapa_user` (first time only) + `CREATE DATABASE` owned by it, `REVOKE CONNECT … FROM PUBLIC`, `GRANT CONNECT, TEMPORARY` to `pmapa_user`. |
| `extensions.sql` | Inside one database: `pg_trgm` + `btree_gist`, created by the admin. |
| `test_database.sql` | Optional `pmapa_<svc>_test` databases for integration tests. |

## Run it

Needs `psql` (`brew install libpq && brew link --force libpq`). Run from the
repository root; the script `cd`s to its own folder, so the `.sql` paths resolve
either way.

    # the usual way — admin password out-of-band, nothing in the process list
    PGPASSWORD=<admin-password> ./env/db/external/provision.sh

    # plus the pmapa_<svc>_test databases used by the integration tests
    PGPASSWORD=<admin-password> ./env/db/external/provision.sh --with-test

    # or pass a full admin URL (avoid if the password contains @ : / ?)
    ./env/db/external/provision.sh "postgres://postgres:pw@80.66.64.227:5432/postgres?sslmode=require"

Overridable via the environment: `DB_HOST`, `DB_PORT`, `DB_SSLMODE` (default
`require`), `DB_ADMIN_USER` (default `postgres`), `DB_ADMIN_DB` (default
`postgres` — `CREATE DATABASE` cannot run while connected to the database being
created).

`sslmode=require` is the default on purpose: this server is reached over the
public internet, and with `sslmode=disable` the password would cross it in
clear text.

## The password is yours, not the script's

The script **never sets and never changes** a password on an existing role. The
`pmapa_user` role is created with `PMAPA_DB_PASSWORD` if that variable is set,
otherwise with the placeholder `change-me`. Set the real one by hand, once:

    psql -h 80.66.64.227 -U postgres -c "ALTER ROLE pmapa_user PASSWORD 'your-password'"

Then use it:

- **local dev** — paste it into the `<SVC>_DATABASE_URL` lines in the root
  `.env` (the script prints them already formatted, all with `pmapa_user`);
- **cloud** (`env/prod/<svc>`) — put it in that service's `.env` under its own
  `<SVC>_POSTGRES_PASSWORD` (e.g. `AUTH_POSTGRES_PASSWORD`); all nine carry the
  same value. The connection string there is baked and password-free; the
  password reaches the service out-of-band via `PGPASSWORD`, so any characters
  are fine — no URL-encoding.

Re-running the script after an `ALTER ROLE` is safe: the existing role is left
untouched and your password survives.

## Why the extensions are created by the admin

`message/0006_search.sql` needs `pg_trgm` and `stay/0002_bookings.sql` needs
`btree_gist`, and `CREATE EXTENSION` requires superuser. The admin installs both
up front, so the migration's `CREATE EXTENSION IF NOT EXISTS` becomes a no-op
and the service role never needs elevated rights. Both go into every database —
an unused extension costs nothing, and no service has to remember which one a
future migration will want.

## Verify

    # the databases exist and are owned by pmapa_user
    psql -h 80.66.64.227 -U postgres -c "\l pmapa_*"

    # pmapa_user can log in to every service database
    PGPASSWORD=<pmapa_user-password> psql "postgres://pmapa_user@80.66.64.227:5432/pmapa_travel?sslmode=require" -c "select current_user, current_database()"

    # extensions are in place
    psql -h 80.66.64.227 -U postgres -d pmapa_message -c "select extname from pg_extension where extname in ('pg_trgm','btree_gist')"

## Related

- [`env/prod`](../../prod) — the cloud deploy units that consume these databases
  (app tier only, no data tier).
- The root [`.env.example`](../../../.env.example) — the `<SVC>_DATABASE_URL`
  block for the local dev stack.
