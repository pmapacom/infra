# env/db/external — provisioning the external Postgres

The stores are **not** in this repo any more: there are no Postgres or Redis
containers, no named volumes and no `<svc>-data` networks. Postgres lives on the
external server `80.66.64.227:5432`, and this folder is what prepares it.

One **database** and one **login role** per service, both named `pmapa_<svc>`:

    pmapa_auth   pmapa_user   pmapa_travel   pmapa_post   pmapa_store
    pmapa_stay   pmapa_message   pmapa_media   pmapa_notification

The travel service connects as role `pmapa_travel` to database `pmapa_travel`
and to nothing else — `CONNECT` is revoked from `PUBLIC` on every database, so
one service cannot open another's database even knowing its name. That is the
isolation the per-service `<svc>-data` networks used to give.

`stats` is not in the list: its only store is the external managed Redis.

## Files

| File | What it does |
|------|--------------|
| `provision.sh` | Driver — loops over the nine services, idempotent. Prints ready-made `<SVC>_DATABASE_URL` lines for the root `.env`. |
| `database.sql` | One service: `CREATE ROLE` + `CREATE DATABASE` (owner = that role), `REVOKE CONNECT … FROM PUBLIC`, `GRANT CONNECT, TEMPORARY` to the role. |
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

## Passwords are yours, not the script's

The script **never sets and never changes** a password on an existing role. A
*new* role is created with `<SVC>_DB_PASSWORD` if that variable is set, otherwise
with the placeholder `change-me`. Set the real one by hand, once per role:

    psql -h 80.66.64.227 -U postgres -c "ALTER ROLE pmapa_travel PASSWORD 'your-password'"

Then use it:

- **local dev** — paste it into the `<SVC>_DATABASE_URL` lines in the root
  `.env` (the script prints them already formatted);
- **cloud** (`env/prod/<svc>`) — put it in that service's `.env` as
  `<SVC>_POSTGRES_PASSWORD`. The connection string there is baked and
  password-free; the password reaches the service out-of-band via `PGPASSWORD`,
  so any characters are fine — no URL-encoding.

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

    # the databases exist and are owned by their own role
    psql -h 80.66.64.227 -U postgres -c "\l pmapa_*"

    # a service can log in to its own database …
    PGPASSWORD=<pmapa_travel-password> psql "postgres://pmapa_travel@80.66.64.227:5432/pmapa_travel?sslmode=require" -c "select current_user, current_database()"

    # … and is refused on someone else's
    PGPASSWORD=<pmapa_travel-password> psql "postgres://pmapa_travel@80.66.64.227:5432/pmapa_auth?sslmode=require" -c "select 1"

    # extensions are in place
    psql -h 80.66.64.227 -U postgres -d pmapa_message -c "select extname from pg_extension where extname in ('pg_trgm','btree_gist')"

## Related

- [`env/prod`](../../prod) — the cloud deploy units that consume these databases
  (app tier only, no data tier).
- The root [`.env.example`](../../../.env.example) — the `<SVC>_DATABASE_URL`
  block for the local dev stack.
