# env/prod/notification — cloud app tier for the notification service

The **stateless** notification service (outbound email via SMTP + in-app activity
feed + push tokens/prefs), deployed from a pre-built image. Mirror of the data
tier in [env/db/notification](../../db/notification). INTERNAL-only for `Notify` /
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
| `IMAGE` | Registry image + tag, e.g. `ghcr.io/pmapa/notification:latest`. |
| `NOTIFICATION_DATABASE_URL` | Managed Postgres URL (activity feed + push tokens/prefs; `sslmode=require`). |
| `NOTIFICATION_SMTP_HOST` | SMTP relay host. Set empty (`NOTIFICATION_SMTP_HOST=`) to log emails instead of sending. |

### Defaulted (override only if needed)

| Variable | Default | Purpose |
|----------|---------|---------|
| `NOTIFICATION_SMTP_PORT` | `587` | `587` STARTTLS / `465` implicit TLS. |
| `NOTIFICATION_SMTP_USERNAME` / `NOTIFICATION_SMTP_PASSWORD` | (empty) | SMTP AUTH credentials. |
| `NOTIFICATION_SMTP_FROM` | `PMapa <no-reply@pmapa.app>` | Email `From` header. |
| `NOTIFICATION_RESET_URL_BASE` | (empty) | Password-reset link base the token is appended to. |

## Requirements

- Managed **PostgreSQL** (via `NOTIFICATION_DATABASE_URL`) — see [env/db/notification](../../db/notification).
- An **SMTP relay** (via `NOTIFICATION_SMTP_*`) for real email; logs instead when host is empty.
- The shared external `pmapa` network.

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
