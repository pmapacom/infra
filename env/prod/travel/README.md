# env/prod/travel — cloud app tier for the travel service

The **stateless** travel service (trips as own-your-data documents, visited
records), deployed from a pre-built image. Mirror of the data tier in
[env/db/travel](../../db/travel). No published port — reachable only through the
[gateway](../gateway). Scale: `docker compose up -d --scale travel=3`.

Full env-var reference: <https://github.com/pmapacom/travel>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `IMAGE` | Registry image + tag, e.g. `ghcr.io/pmapa/travel:latest`. |
| `DATABASE_URL` | Managed Postgres URL (use `sslmode=require`). |

### Defaulted (override only if needed)

| Variable | Default | Purpose |
|----------|---------|---------|
| `TRAVEL_STATS_URL` | `http://stats:8080` | Metric reconcile; empty ⇒ metrics disabled. |

## Requirements

- Managed **PostgreSQL** (via `DATABASE_URL`) — see [env/db/travel](../../db/travel).
- The shared external `pmapa` network.

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
