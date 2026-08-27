# env/prod/post — cloud app tier for the post service

The **stateless** post service (posts, likes/saves/comments, reviews, feed),
deployed from a pre-built image. Mirror of the data tier in
[env/db/post](../../db/post). No published port — reachable only through the
[gateway](../gateway). Scale: `docker compose up -d --scale post=3`.

Full env-var reference: <https://github.com/pmapacom/post>.

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
| `POST_USER_URL` | `http://user:8080` | Feed followees + privacy/blocking gate. Unreachable ⇒ feed fails closed. |
| `POST_STATS_URL` | `http://stats:8080` | Metric pushes; empty ⇒ metrics disabled. |
| `POST_NOTIFICATION_URL` | `http://notification:8080` | Like/comment events; empty ⇒ disabled. |

## Requirements

- Managed **PostgreSQL** (via `DATABASE_URL`) — see [env/db/post](../../db/post).
- In-cluster **user** service (feed); **stats** / **notification** optional.
- The shared external `pmapa` network.

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
