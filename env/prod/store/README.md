# env/prod/store — cloud app tier for the store service

The **stateless** store service (goods classifieds + favourites), deployed from a
pre-built image. Mirror of the data tier in [env/db/store](../../db/store). No
published port — reachable only through the [gateway](../gateway). Scale:
`docker compose up -d --scale store=3`.

Full env-var reference: <https://github.com/pmapacom/store>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Managed Postgres URL (use `sslmode=require`). |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `STORE_STATS_URL` | `http://stats:8080` | Metric reconcile; empty ⇒ metrics disabled. |

## Requirements

- Managed **PostgreSQL** (via `DATABASE_URL`) — see [env/db/store](../../db/store).
- The shared external `pmapa` network.

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
