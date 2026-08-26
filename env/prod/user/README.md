# env/prod/user — cloud app tier for the user service

The **stateless** user service (profiles, follow graph, discovery, moderation),
deployed from a pre-built image. Mirror of the data tier in
[env/db/user](../../db/user). No published port — reachable only through the
[gateway](../gateway). Scale: `docker compose up -d --scale user=3`.

Full env-var reference: <https://github.com/pmapacom/user>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `IMAGE` | Registry image + tag, e.g. `ghcr.io/pmapa/user:latest`. |
| `DATABASE_URL` | Managed Postgres URL (use `sslmode=require`). |

### Defaulted (override only if needed)

| Variable | Default | Purpose |
|----------|---------|---------|
| `USER_STATS_URL` | `http://stats:8080` | Metric pushes; empty ⇒ metrics disabled. |
| `USER_NOTIFICATION_URL` | `http://notification:8080` | In-app follow events; empty ⇒ disabled. |
| `USER_ADMIN_IDS` | (empty) | Comma-separated moderator user ids (unlocks the Moderation queue). |

## Requirements

- Managed **PostgreSQL** (via `DATABASE_URL`) — see [env/db/user](../../db/user).
- The shared external `pmapa` network.

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
