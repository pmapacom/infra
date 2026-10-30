# env/prod/message — cloud app tier for the message service

The **stateless** message service (1:1 + group chat, governance, live `Subscribe`
stream, search, retention), deployed from a pre-built image. Its only store is
the **external** managed Postgres — nothing stateful runs on this box.
No published port — reachable only
through the [gateway](../gateway). Scale: `docker compose up -d --scale message=3`.

Full env-var reference: <https://github.com/pmapacom/message>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `MESSAGE_POSTGRES_PASSWORD` | Password of the role `pmapa_message` on the external Postgres — host/db/user are baked. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `MESSAGE_USER_URL` | `http://user:8080` | DM block gate (fails open on transient errors); empty ⇒ gate disabled. |
| `MESSAGE_NOTIFICATION_URL` | `http://notification:8080` | `message.new` events; empty ⇒ no chat notifications. |
| `MESSAGE_STATS_URL` | `http://stats:8080` | Metric pushes; empty ⇒ metrics disabled. |

> Rate limiting and disappearing-message retention are **not** env-configured —
> rate limits are in-code constants; retention is per-conversation state in Postgres.

## Requirements

- **PostgreSQL** — external: database `pmapa_message` on `80.66.64.227:5432`, login
  role `pmapa_message`, `sslmode=require` (see [env/db/external](../../db/external)).
  The `pg_trgm` / `btree_gist` extensions are created by `provision.sh`.
- In-cluster **user** / **stats** / **notification** (all optional, degrade gracefully).
- Networks: `pmapa` only (service RPC + the route out to the external Postgres).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
