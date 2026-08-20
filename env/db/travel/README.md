# env/db/travel — data tier for the travel service

Brings up the **stateful** dependency of the travel service: PostgreSQL (the
user's trips, stored as opaque client-owned documents). No Redis — the travel
service holds no ephemeral security state (it trusts the gateway-verified
`X-User-Id` and verifies nothing itself).

Same topology as [env/db/user](../user/README.md): **one** logical database,
**many** stateless app replicas. Runs on host port **5434** by default so it
coexists with the auth (5432) and user (5433) data tiers.

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # postgres healthy
```

Connection string for the travel service:

```
DATABASE_URL=postgres://travel:devpass@localhost:5434/travel?sslmode=disable
```

## Cloud

Map to a managed Postgres instance; the travel app replicas scale independently
and connect via `DATABASE_URL`.
