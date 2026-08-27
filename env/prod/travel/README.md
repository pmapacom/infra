# env/prod/travel — cloud app tier for the travel service

The **stateless** travel service (trips as own-your-data documents, visited
records), deployed from a pre-built image. Mirror of the data tier in
[env/prod/infra](../infra). No published port — reachable only through the
[gateway](../gateway). Scale: `docker compose up -d --scale travel=3`.

Full env-var reference: <https://github.com/pmapacom/travel>.

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
| `TRAVEL_STATS_URL` | `http://stats:8080` | Metric reconcile; empty ⇒ metrics disabled. |

## Requirements

- **PostgreSQL** (via `DATABASE_URL`) — see [env/prod/infra](../infra).
- Networks: `pmapa` (service RPC) + `travel-data` (its store) — see [env/prod/infra](../infra).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
