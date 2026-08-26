# env/db/stats — data tier for the stats service

Brings up the **stateful** dependency of the stats service: a single Redis that
holds every named metric (`Set`/`Inc` → `Get`/`BatchGet`). Password-protected
with AOF persistence so metrics survive a restart. No Postgres — stats keeps
nothing relational.

Same topology as [env/db/auth](../auth/README.md)'s Redis: **one** logical store,
**many** stateless app replicas. Runs on host port **6380** by default so it
coexists with the auth data tier's Redis (6379).

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # redis healthy
```

Connection string for the stats service:

```
REDIS_URL=redis://:devpass@localhost:6380/0
```

## Cloud

Map to a managed Redis instance; the stats app replicas scale independently and
connect via `REDIS_URL`. Pair with the app tier in [env/prod/stats](../../prod/stats).
