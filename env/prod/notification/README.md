# env/prod/notification — cloud app tier for the notification service

The **stateless** notification service (outbound email via SMTP + in-app activity
feed + push tokens/prefs), deployed from a pre-built image. Its only store is
the **external** managed Postgres — nothing stateful runs on this box.
INTERNAL-only for `Notify` /
`SendEmail` s2s; its read/prefs RPCs are gateway-routed. No published port. Scale:
`docker compose up -d --scale notification=3`.

Full env-var reference: <https://github.com/pmapacom/notification>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

> Note: this service uses **`NOTIFICATION_DATABASE_URL`**, not the shared
> `DATABASE_URL`.

### Must set

| Variable | Purpose |
|----------|---------|
| `NOTIFICATION_POSTGRES_PASSWORD` | Shared Postgres password (role `pmapa_user`) — host and database (`pmapa_notification`) are baked. |
| `NOTIFICATION_SMTP_HOST` | SMTP relay host. Set empty (`NOTIFICATION_SMTP_HOST=`) to log emails instead of sending. |

### Optional (in .env)

| Variable | Purpose |
|----------|---------|
| `NOTIFICATION_SMTP_USERNAME` / `NOTIFICATION_SMTP_PASSWORD` | SMTP AUTH credentials; unset ⇒ unauthenticated relay. |
| `NOTIFICATION_RESET_URL_BASE` | Password-reset link base the token is appended to; unset ⇒ bare code. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `NOTIFICATION_SMTP_PORT` | `587` | `587` STARTTLS / `465` implicit TLS. |
| `NOTIFICATION_SMTP_FROM` | `PMapa <no-reply@pmapa.app>` | Email `From` header. |

## Requirements

- **PostgreSQL** — external: database `pmapa_notification` on `80.66.64.227:5432`,
  shared login role `pmapa_user`, `sslmode=require`
  (see [env/db/external](../../db/external)).
- An **SMTP relay** (via `NOTIFICATION_SMTP_*`) for real email; logs instead when host is empty.
- Networks: `pmapa` only (service RPC + the routes out to the external Postgres and SMTP).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
