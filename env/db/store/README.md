# env/db/store — data tier for the store service

Brings up the **stateful** dependency of the store service: PostgreSQL (goods classifieds + favourites). No Redis — the store service holds no
ephemeral security state (it trusts the gateway-verified `X-User-Id` and
verifies nothing itself).

Same topology as [env/db/user](../user/README.md): **one** logical database,
**many** stateless app replicas. Runs on host port **5436** by default so it
coexists with the auth (5432), user (5433) and travel (5434) data tiers.

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # postgres healthy
```

Connection string for the store service:

```
DATABASE_URL=postgres://store:devpass@localhost:5436/store?sslmode=disable
```

For service tests, create a `store_test` database in this instance
(`createdb -h localhost -p 5436 -U store store_test`) — the suite connects to
`postgres://store:devpass@localhost:5436/store_test` and skips when unreachable.

## Cloud

Map to a managed Postgres instance; the store app replicas scale independently
and connect via `DATABASE_URL`.
