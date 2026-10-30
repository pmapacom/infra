# env/prod/auth — cloud app tier for the auth service

The **stateless** auth service (identity, sessions, DPoP, account deletion),
deployed from a pre-built image. Both of its stores are **external** (managed
Postgres + managed Redis) — nothing stateful runs on this box. No published
port — reachable only through the
[gateway](../gateway). Scale horizontally: `docker compose up -d --scale auth=3`.

Full env-var reference (from the code) lives in the service repo:
<https://github.com/pmapacom/auth>.

## Environment

Copy `.env.example` → `.env` and fill it (`docker compose` reads `.env`).
Vars marked **must set** are `${VAR:?}` in the compose — boot fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `PMAPA_DB_PASSWORD` | Shared Postgres password (role `pmapa_user`) — host and database (`pmapa_auth`) are baked. |
| `AUTH_REDIS_PASSWORD` | Password for the external Redis (session deny-list + DPoP replay). Same value as `STATS_REDIS_PASSWORD` (shared instance). |
| `AUTH_SIGNING_KEY_SEED` | Base64 32-byte Ed25519 seed shared across replicas — `openssl rand -base64 32`. Empty ⇒ ephemeral per-process key (dev only). |

### Optional (in .env)

| Variable | Purpose |
|----------|---------|
| `AUTH_OIDC_GOOGLE_CLIENT_IDS` / `AUTH_OIDC_APPLE_CLIENT_IDS` | Accepted OIDC client ids (comma-separated); unset ⇒ that social login disabled. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `AUTH_ACCESS_TTL` | `10m` | Access-token lifetime. |
| `AUTH_NOTIFICATION_URL` | `http://notification:8080` | Password-reset email delivery. |
| `AUTH_USER_URL` / `AUTH_POST_URL` / `AUTH_TRAVEL_URL` / `AUTH_MESSAGE_URL` / `AUTH_MEDIA_URL` | `http://<svc>:8080` | Account-deletion `PurgeUser` fan-out targets. |

## Requirements

- **PostgreSQL** — external, `80.66.64.227:5432`, database `pmapa_auth`, shared
  login role `pmapa_user` (`sslmode=require`); see [env/db/external](../../db/external).
- **Redis** — external managed instance
  `generative-thorough-birthday-92146.db.redis.io:18624`, user `default`, db 0.
  Keys are confined to `deny:*`, `dpop:*` and `fail:*`.
- Network: `pmapa` only (service RPC + the route out to both stores); see
  [../README.md](../README.md).
- For working password resets: a reachable `notification` service + its SMTP config.

## Deploy

```bash
docker network create pmapa            # once per host (see ../README.md)
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
docker compose logs -f auth
```
