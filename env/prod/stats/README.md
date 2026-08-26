# env/prod/stats — cloud app tier for the stats service

The **stateless** stats service (generic named-metric store), deployed from a
pre-built image. Mirror of the data tier in [env/db/stats](../../db/stats).
INTERNAL-only: no gateway route, no published port — reachable only inside the
cluster. Scale: `docker compose up -d --scale stats=3`.

Full env-var reference: <https://github.com/pmapacom/stats>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `IMAGE` | Registry image + tag, e.g. `ghcr.io/pmapa/stats:latest`. |
| `REDIS_URL` | Managed Redis URL (the metric store). |

_No other configuration — `STATS_HTTP_ADDR` defaults to `:8080`._

## Requirements

- Managed **Redis** (via `REDIS_URL`) — see [env/db/stats](../../db/stats).
- The shared external `pmapa` network.

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
