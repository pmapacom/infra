# env/prod/stats — cloud app tier for the stats service

The **stateless** stats service (generic named-metric store), deployed from a
pre-built image. Its only store is the **external managed Redis** — nothing
stateful runs on this box.
INTERNAL-only: no gateway route, no published port — reachable only inside the
cluster. Scale: `docker compose up -d --scale stats=3`.

Full env-var reference: <https://github.com/pmapacom/stats>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `STATS_REDIS_PASSWORD` | Password for the external Redis — host/user/db are baked. Same value as `AUTH_REDIS_PASSWORD` (shared instance). |

_No other configuration — `STATS_HTTP_ADDR` defaults to `:8080`._

## Requirements

- **Redis** — external managed instance
  `generative-thorough-birthday-92146.db.redis.io:18624`, user `default`, db 0.
  Keys are confined to `metric:*`.
- Network: `pmapa` only (service RPC + the route out to Redis).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
