# env/db/post — data tier for the post service

Brings up the **stateful** dependency of the post service: PostgreSQL (posts,
likes, saves, comments, reviews). No Redis — the post service holds no
ephemeral security state (it trusts the gateway-verified `X-User-Id` and
verifies nothing itself).

Same topology as [env/db/user](../user/README.md): **one** logical database,
**many** stateless app replicas. Runs on host port **5435** by default so it
coexists with the auth (5432), user (5433) and travel (5434) data tiers.

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # postgres healthy
```

Connection string for the post service:

```
DATABASE_URL=postgres://post:devpass@localhost:5435/post?sslmode=disable
```

For service tests, create a `post_test` database in this instance
(`createdb -h localhost -p 5435 -U post post_test`) — the suite connects to
`postgres://post:devpass@localhost:5435/post_test` and skips when unreachable.

## Cloud

Map to a managed Postgres instance; the post app replicas scale independently
and connect via `DATABASE_URL`.
