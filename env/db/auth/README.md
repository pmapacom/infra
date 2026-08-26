# env/db/auth — data tier for the auth service

Brings up the **stateful** dependencies of the auth service: PostgreSQL (users,
sessions, identities, password resets) and Redis (access-token revocation
denylist + rate limiting).

## Topology (applies to every service)

```
                 ┌──────────── app tier (stateless, N replicas) ───────────┐
   nginx ──────► │  auth #1   auth #2   auth #3   …  (scale horizontally)   │
                 └───────────────────────┬──────────────────────────────────┘
                                         │  DATABASE_URL / REDIS_URL
                 ┌───────────────────────▼─────── data tier (1 instance) ───┐
                 │   Postgres  +  Redis   (this compose / managed in cloud)  │
                 └───────────────────────────────────────────────────────────┘
```

- **One** logical database; **many** app instances. All shared state lives here,
  never in an app process — so any replica can serve any request.
- The auth app is stateless: signing keys come from a shared secret (not
  per-instance), the revocation denylist lives in Redis, schema migrations run
  as a separate one-off step (not on every replica boot).

## Local

```bash
cp .env.example .env         # already present for dev
docker compose up -d
docker compose ps            # postgres + redis healthy
```

Connection strings for the auth service:

```
DATABASE_URL=postgres://auth:devpass@localhost:5432/auth?sslmode=disable
REDIS_URL=redis://:devpass@localhost:6379/0
```

## Cloud

Point the auth service at a managed Postgres + Redis instead (same env vars).
This compose is a single data host; do **not** run it per app replica.
