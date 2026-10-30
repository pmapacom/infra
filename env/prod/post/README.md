# env/prod/post — cloud app tier for the post service

The **stateless** post service (posts, likes/saves/comments, reviews, feed),
deployed from a pre-built image. Its only store is the **external** managed
Postgres — nothing stateful runs on this box. No published port — reachable
only through the
[gateway](../gateway). Scale: `docker compose up -d --scale post=3`.

Full env-var reference: <https://github.com/pmapacom/post>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `PMAPA_DB_PASSWORD` | Shared Postgres password (role `pmapa_user`) — host and database (`pmapa_post`) are baked. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `POST_USER_URL` | `http://user:8080` | Feed followees + privacy/blocking gate. Unreachable ⇒ feed fails closed. |
| `POST_STATS_URL` | `http://stats:8080` | Metric pushes; empty ⇒ metrics disabled. |
| `POST_NOTIFICATION_URL` | `http://notification:8080` | Like/comment events; empty ⇒ disabled. |

## Requirements

- **PostgreSQL** — external: database `pmapa_post` on `80.66.64.227:5432`, shared
  login role `pmapa_user`, `sslmode=require` (see [env/db/external](../../db/external)).
- In-cluster **user** service (feed); **stats** / **notification** optional.
- Networks: `pmapa` only (service RPC + the route out to the external Postgres).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
