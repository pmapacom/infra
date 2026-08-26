# env/db/notification — data tier for the notification service

Brings up the **stateful** dependency of the notification service: PostgreSQL
(the in-app activity feed, push tokens + prefs, and delivery bookkeeping). No
Redis — SMTP delivery is stateless.

Same topology as [env/db/user](../user/README.md): **one** logical database, **many**
stateless app replicas. Runs on host port **5439** by default so it coexists with
the other domain data tiers.

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose ps            # postgres healthy
```

Connection string for the notification service:

```
NOTIFICATION_DATABASE_URL=postgres://notification:devpass@localhost:5439/notification?sslmode=disable
```

## Cloud

Map to a managed Postgres instance; the notification app replicas scale
independently and connect via `NOTIFICATION_DATABASE_URL`. Pair with the
app tier in [env/prod/notification](../../prod/notification).
