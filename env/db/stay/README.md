# env/db/stay — data tier for the stay service

Brings up the **stateful** dependency of the stay service: PostgreSQL (rent and
buy listings, plus per-account favourites). No Redis — the stay service holds no
ephemeral security state (it trusts the gateway-verified `X-User-Id` and
verifies nothing itself).

Same topology as [env/db/user](../user/README.md): **one** logical database,
**many** stateless app replicas. Runs on host port **5440** by default so it
coexists with the auth (5432), user (5433), travel (5434) and store (5436) data
tiers.

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # postgres healthy
```

Connection string for the stay service:

```
DATABASE_URL=postgres://stay:devpass@localhost:5440/stay?sslmode=disable
```

`seed.sql` holds demo listings for local work. It is **development only** — it
inserts with `ON CONFLICT DO NOTHING`, so applying it twice is harmless:

```bash
psql postgres://stay:devpass@localhost:5440/stay -f seed.sql
```

For service tests, create a `stay_test` database in this instance
(`createdb -h localhost -p 5440 -U stay stay_test`) — the suite connects to
`postgres://stay:devpass@localhost:5440/stay_test` and skips when unreachable.

## Cloud

Map to a managed Postgres instance; the stay app replicas scale independently
and connect via `DATABASE_URL`.
