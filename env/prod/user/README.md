# env/prod/user — cloud app tier for the user service

The **stateless** user service (profiles, follow graph, discovery, moderation),
deployed from a pre-built image. Its only store is the **external** managed
Postgres — nothing stateful runs on this box. No published port — reachable
only through the
[gateway](../gateway). Scale: `docker compose up -d --scale user=3`.

Full env-var reference: <https://github.com/pmapacom/user>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `USER_POSTGRES_PASSWORD` | Password of the role `pmapa_user` on the external Postgres — host/db/user are baked. |

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

- **PostgreSQL** — external: database `pmapa_user` on `80.66.64.227:5432`, login
  role `pmapa_user`, `sslmode=require` (see [env/db/external](../../db/external)).
- Networks: `pmapa` only (service RPC + the route out to the external Postgres).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
