# env/db/message — data tier for the message service

Brings up the **stateful** dependency of the message service: PostgreSQL (conversations, memberships, messages). No Redis — the message service holds no
ephemeral security state (it trusts the gateway-verified `X-User-Id` and
verifies nothing itself).

Same topology as [env/db/user](../user/README.md): **one** logical database,
**many** stateless app replicas. Runs on host port **5437** by default so it
coexists with the auth (5432), user (5433) and travel (5434) data tiers.

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # postgres healthy
```

Connection string for the message service:

```
DATABASE_URL=postgres://message:devpass@localhost:5437/message?sslmode=disable
```

For service tests, create a `message_test` database in this instance
(`createdb -h localhost -p 5437 -U message message_test`) — the suite connects to
`postgres://message:devpass@localhost:5437/message_test` and skips when unreachable.

## Cloud

Map to a managed Postgres instance; the message app replicas scale independently
and connect via `DATABASE_URL`.
