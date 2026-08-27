# env/prod/user — cloud app tier for the user service

The **stateless** user service (profiles, follow graph, discovery, moderation),
deployed from a pre-built image. Mirror of the data tier in
[env/prod/infra](../infra). No published port — reachable only through the
[gateway](../gateway). Scale: `docker compose up -d --scale user=3`.

Full env-var reference: <https://github.com/pmapacom/user>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `USER_POSTGRES_PASSWORD` | Postgres password — host/db/user are baked. Must equal `USER_POSTGRES_PASSWORD` in infra. |

### Optional (in .env)

| Variable | Purpose |
|----------|---------|
| `USER_ADMIN_IDS` | Comma-separated moderator user ids (unlocks the Moderation queue); unset ⇒ no admins. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `USER_STATS_URL` | `http://stats:8080` | Metric pushes; empty ⇒ metrics disabled. |
| `USER_NOTIFICATION_URL` | `http://notification:8080` | In-app follow events; empty ⇒ disabled. |

## Requirements

- **PostgreSQL** (via `DATABASE_URL`) — see [env/prod/infra](../infra).
- Networks: `pmapa` (service RPC) + `user-data` (its store) — see [env/prod/infra](../infra).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
