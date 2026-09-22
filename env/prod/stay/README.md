# env/prod/stay — cloud app tier for the stay service

The **stateless** stay service (rent/buy listings, search filters and
favourites), deployed from a pre-built image. Mirror of the data tier in
[env/prod/infra](../infra). No published port — reachable only through the
[gateway](../gateway). Scale: `docker compose up -d --scale stay=3`.

Browsing is public: the gateway routes `ListStays` and `GetStay` without
`auth_request`, so a signed-out visitor can search. Everything that writes a
listing or a favourite stays behind authentication.

Full env-var reference: <https://github.com/pmapacom/stay>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `STAY_POSTGRES_PASSWORD` | Postgres password — host/db/user are baked. Must equal `STAY_POSTGRES_PASSWORD` in infra. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `STAY_STATS_URL` | `http://stats:8080` | Metric reconcile; empty ⇒ metrics disabled. |

## Requirements

- **PostgreSQL** (via `DATABASE_URL`) — see [env/prod/infra](../infra).
- Networks: `pmapa` (service RPC) + `stay-data` (its store) — see [env/prod/infra](../infra).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
