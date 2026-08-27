# env/prod/message — cloud app tier for the message service

The **stateless** message service (1:1 + group chat, governance, live `Subscribe`
stream, search, retention), deployed from a pre-built image. Mirror of the data
tier in [env/prod/infra](../infra). No published port — reachable only
through the [gateway](../gateway). Scale: `docker compose up -d --scale message=3`.

Full env-var reference: <https://github.com/pmapacom/message>.

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
| `MESSAGE_USER_URL` | `http://user:8080` | DM block gate (fails open on transient errors); empty ⇒ gate disabled. |
| `MESSAGE_NOTIFICATION_URL` | `http://notification:8080` | `message.new` events; empty ⇒ no chat notifications. |
| `MESSAGE_STATS_URL` | `http://stats:8080` | Metric pushes; empty ⇒ metrics disabled. |

> Rate limiting and disappearing-message retention are **not** env-configured —
> rate limits are in-code constants; retention is per-conversation state in Postgres.

## Requirements

- **PostgreSQL** (via `DATABASE_URL`) — see [env/prod/infra](../infra).
- In-cluster **user** / **stats** / **notification** (all optional, degrade gracefully).
- Networks: `pmapa` (service RPC) + `message-data` (its store) — see [env/prod/infra](../infra).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
