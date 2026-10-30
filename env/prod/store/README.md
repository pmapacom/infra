# env/prod/store — cloud app tier for the store service

The **stateless** store service (goods classifieds + favourites), deployed from a
pre-built image. Its only store is the **external** managed Postgres — nothing
stateful runs on this box. No published port — reachable only through the
[gateway](../gateway). Scale:
`docker compose up -d --scale store=3`.

Full env-var reference: <https://github.com/pmapacom/store>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `STORE_POSTGRES_PASSWORD` | Shared Postgres password (role `pmapa_user`) — host and database (`pmapa_store`) are baked. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `STORE_STATS_URL` | `http://stats:8080` | Metric reconcile; empty ⇒ metrics disabled. |

## Requirements

- **PostgreSQL** — external: database `pmapa_store` on `80.66.64.227:5432`, shared
  login role `pmapa_user`, `sslmode=require` (see [env/db/external](../../db/external)).
- Networks: `pmapa` only (service RPC + the route out to the external Postgres).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
