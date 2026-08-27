# env/prod/infra — on-box data tier (all DBs + storage)

The whole **stateful** backing tier for a single-machine deployment: one Postgres
per service, Redis for auth + stats, and MinIO (S3) for media. One `docker
compose up` here brings up everything the app services need to connect to.

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
   media──[ media-data (internal) ]── media-postgres, minio
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
| `message-data` | message-postgres | message |
| `media-data` | media-postgres, minio | media |
| `notification-data` | notification-postgres | notification |
| `stats-data` | stats-redis | stats |

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
- **MinIO.** The `minio-init` one-shot creates the `MEDIA_S3_BUCKET`. MinIO needs
  path-style addressing — the media service ships with `MEDIA_S3_PATH_STYLE=true`.
- **SMTP** is not part of this tier: notification uses an external relay (or logs
  when `NOTIFICATION_SMTP_HOST` is empty).
