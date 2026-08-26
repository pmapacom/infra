# env/db/user — data tier for the user service

Brings up the **stateful** dependency of the user service: PostgreSQL (profiles +
the follow graph). No Redis — the user service holds no ephemeral security state
(it trusts the gateway-verified `X-User-Id` and verifies nothing itself).

Same topology as [env/db/auth](../auth/README.md): **one** logical database, **many**
stateless app replicas. Runs on host port **5433** by default so it coexists with
the auth data tier (5432).

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # postgres healthy
```

Connection string for the user service:

```
DATABASE_URL=postgres://user:devpass@localhost:5433/user?sslmode=disable
```

## Cloud

Map to a managed Postgres instance; the user app replicas scale independently and
connect via `DATABASE_URL`.
