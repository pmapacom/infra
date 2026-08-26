# env/db/media — data tier for the media service

Brings up the **stateful** dependency of the media service: PostgreSQL (image blobs (S3/CDN later)). No Redis — the media service holds no
ephemeral security state (it trusts the gateway-verified `X-User-Id` and
verifies nothing itself).

Same topology as [env/db/user](../user/README.md): **one** logical database,
**many** stateless app replicas. Runs on host port **5438** by default so it
coexists with the auth (5432), user (5433) and travel (5434) data tiers.

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # postgres healthy
```

Connection string for the media service:

```
DATABASE_URL=postgres://media:devpass@localhost:5438/media?sslmode=disable
```

For service tests, create a `media_test` database in this instance
(`createdb -h localhost -p 5438 -U media media_test`) — the suite connects to
`postgres://media:devpass@localhost:5438/media_test` and skips when unreachable.

## Cloud

Map to a managed Postgres instance; the media app replicas scale independently
and connect via `DATABASE_URL`.
