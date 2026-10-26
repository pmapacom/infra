# env/prod/infra — on-box data tier (all DBs)

The whole **stateful** backing tier for a single-machine deployment: one Postgres
per service and Redis for auth + stats. One `docker compose up` here brings up
everything the app services need to connect to.

There is **no object store on this box**: media bytes live in Cloudflare R2 and
are read through the Cloudflare CDN, so `media-postgres` holds only the id ↔
object metadata. See [env/prod/media](../media).

Use this when you're running the entire stack on one box. The per-service data
tiers under [env/db/*](../../db) still exist for isolated single-service runs;
this file is the consolidated equivalent, wired for the `env/prod` app tier.

## Network isolation

Each store sits on its **own internal network** — nothing else can reach it:

```
   auth  ──[ pmapa ]── user … (RPC between services)
    │
    └──[ auth-data (internal) ]── auth-postgres, auth-redis
   user ──[ user-data (internal) ]── user-postgres
   media──[ media-data (internal) ]── media-postgres   (bytes → Cloudflare R2)
   …
```

- An app service joins **two** networks: `pmapa` (talk to other services) and its
  own `<svc>-data` (talk to its store). The post service literally has no route to
  auth's database.
- `<svc>-data` networks are `internal: true` — the stores have no path off-box.
- This is also what makes **extracting a DB later** clean: the boundary already
  exists, so you just repoint one `DATABASE_URL` and remove that store here.

| Network | Stores on it | Joined by |
|---------|--------------|-----------|
| `auth-data` | auth-postgres, auth-redis | auth |
| `user-data` | user-postgres | user |
| `travel-data` | travel-postgres | travel |
| `post-data` | post-postgres | post |
| `store-data` | store-postgres | store |
| `stay-data` | stay-postgres | stay |
| `message-data` | message-postgres | message |
| `media-data` | media-postgres | media |
| `notification-data` | notification-postgres | notification |
| `stats-data` | stats-redis | stats |

## Environment

Copy `.env.example` → `.env` and set **every** value below — all are `${VAR:?}`,
so the compose refuses to start with any left blank. Each password must equal the
one in the matching service's connection string (`env/prod/<svc>/.env`); the
reference block at the bottom of `.env.example` lists those strings.

> **Passwords can contain any characters.** Services receive them out-of-band
> (`PGPASSWORD` / `REDIS_PASSWORD`), never inside a connection URL, so there's no
> URL-encoding to worry about. Generate however you like, e.g.
> `openssl rand -base64 30`.

### Postgres passwords (one per service)

| Variable | Store |
|----------|-------|
| `AUTH_POSTGRES_PASSWORD` | auth-postgres |
| `USER_POSTGRES_PASSWORD` | user-postgres |
| `TRAVEL_POSTGRES_PASSWORD` | travel-postgres |
| `POST_POSTGRES_PASSWORD` | post-postgres |
| `STORE_POSTGRES_PASSWORD` | store-postgres |
| `STAY_POSTGRES_PASSWORD` | stay-postgres |
| `MESSAGE_POSTGRES_PASSWORD` | message-postgres |
| `MEDIA_POSTGRES_PASSWORD` | media-postgres |
| `NOTIFICATION_POSTGRES_PASSWORD` | notification-postgres |

### Redis passwords

| Variable | Store |
|----------|-------|
| `AUTH_REDIS_PASSWORD` | auth-redis |
| `STATS_REDIS_PASSWORD` | stats-redis |

### Object storage

Nothing to set here. The media service reaches **Cloudflare R2** directly over
the public internet with its own API token — that credential lives in
`env/prod/media/.env`, not in this file.

## Deploy — bring this up **first**

```bash
docker network create pmapa            # shared app-tier network (once per host)
cp .env.example .env && $EDITOR .env   # set all passwords
docker compose up -d
docker compose ps                      # wait until every store is healthy
```

Then bring up the app services (each `env/prod/<svc>`) and finally the gateway.
The default connection strings in every `env/prod/<svc>/.env.example` already
point at the container names above — just keep the passwords in sync with this
`.env` (see the reference block at the bottom of `.env.example`).

## Notes

- **Persistence.** Every store uses a named volume, so data survives
  `docker compose down`. `docker compose down -v` wipes it — don't, in prod.
- **No published ports.** The stores are reachable only over their internal
  network. To inspect one from the host temporarily, add a `ports:` mapping (bind
  `127.0.0.1`) to that service — don't leave it in.
- **Media bytes are off-box.** They are in Cloudflare R2, so they are not covered
  by any volume or backup here — only the metadata in `media-postgres` is. The
  bucket's own durability and lifecycle are managed in Cloudflare.
- **SMTP** is not part of this tier: notification uses an external relay (or logs
  when `NOTIFICATION_SMTP_HOST` is empty).
