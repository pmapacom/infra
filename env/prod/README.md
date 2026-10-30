# env/prod — cloud deploy units (app tier)

One `docker-compose.yml` **per service**, and every one of them is **stateless**:
all stores are external, so nothing on this box holds data.

    env/prod/<svc>   ── app tier (pulls an image, no state, no volumes)
          │
          ├─ DATABASE_URL  ──►  external Postgres 80.66.64.227:5432
          │                     one database per service (pmapa_<svc>), one
          │                     shared login role pmapa_user (see env/db/external)
          ├─ REDIS_URL     ──►  external managed Redis (auth + stats, db 0)
          └─ S3 + CDN      ──►  Cloudflare R2 + CDN (media bytes only)

There is **no data tier in this repo any more** — `env/prod/infra` is gone. No
Postgres or Redis containers, no named volumes, no `<svc>-data` networks: a box
running these composes can be wiped and rebuilt without losing state.

These composes **pull pre-built images** from a registry. Defaults (image, listen
addr, in-cluster URLs, ports) are baked into each compose; only the values with
no sensible default — secrets, connection strings — come from `.env`.

## What's here

| Folder | Service | Published? |
|--------|---------|------------|
| `gateway/` | nginx front door (auth_request → routes by domain) | **yes** — the only public port |
| `front/` | Next.js web frontend (SSR, same-origin with the API) — no state, no `.env` | no |
| `auth/` | auth (EdDSA JWT + DPoP + refresh) — external Postgres + Redis | no |
| `user/` | user/profile + follow graph — external Postgres | no |
| `travel/` | trips document store — external Postgres | no |
| `post/` | posts/feed — external Postgres | no |
| `store/` | goods classifieds — external Postgres | no |
| `stay/` | rent/buy listings — external Postgres, **public browsing** | no |
| `message/` | chat — external Postgres | no |
| `media/` | image uploads → Cloudflare R2, reads via the CDN — external Postgres + an R2 bucket | no |
| `notification/` | email + in-app feed + push — external Postgres + SMTP | no |
| `stats/` | metric store — external Redis | no |
| `geo/` | place dictionary (countries + cities) — no state, **public route** | no |
| `telegrambot/` | ops alerts (opt-in) | no |

Every service listens on `:8080` inside the network and is reachable **only via
the gateway** — none publish a host port. Cross-service calls use the service
name as DNS (`http://user:8080`, `http://stats:8080`, …), resolved by the shared
network below.

## Networks

- **`pmapa`** — the one shared network, for service-to-service RPC. Created once
  by hand (below); every app service and the gateway join it. It is also the
  route out to the external Postgres/Redis and to Cloudflare.

That is the only network now. With the stores off-box there is no per-service
`<svc>-data` network left. Each service still has its own database
(`pmapa_<svc>`), but they all log in as one shared role `pmapa_user`: every
service runs on the same host behind the database's IP firewall, so a leaked
password exposes them all regardless — per-service roles would buy no real
isolation. The trust boundary is the firewall, not the role.

## Deploy — databases first, gateway last

    # 1. one-time: the shared network + a registry login
    docker network create pmapa
    docker login ghcr.io

    # 2. one-time: the external databases — idempotent, run from the repo root.
    # Creates role + database pmapa_<svc> and the pg_trgm/btree_gist extensions.
    PGPASSWORD=<admin-password> ./env/db/external/provision.sh
    # The script never sets or changes the password — you do, once:
    # psql -h 80.66.64.227 -U postgres -c "ALTER ROLE pmapa_user PASSWORD '...'"

    # 3. each service — fill its .env with that password (URLs are baked)
    cd env/prod/auth
    cp .env.example .env && $EDITOR .env
    docker compose pull && docker compose up -d
    # repeat for user, travel, post, store, stay, message, media,
    # notification, stats, geo

    # 4. the web frontend, then the front door, last (neither needs an .env)
    cd ../front && docker compose pull && docker compose up -d
    cd ../gateway && docker compose up -d

Scale a stateless service horizontally (the gateway load-balances via Docker DNS):

    cd env/prod/auth && docker compose up -d --scale auth=3

## Notes

- **Images.** The image + tag is baked into each `docker-compose.yml`
  (`image: ghcr.io/pmapacom/<svc>:latest`) — edit that line to pin a tag.
- **`geo` has no `.env`.** It is the one service with no database and no
  secrets: both dictionaries are baked into its image, so a container is
  disposable. Its gateway route is **public** (no `auth_request`) — a place
  dictionary is not user data and `/explore` must work signed-out. That route
  ships in the gateway image, so adding it needs a gateway redeploy; until
  `geo` is up the route answers 502, which is why it is worth starting first.
- **What goes in `.env`.** Only secrets — the Postgres/Redis **passwords**, the
  signing seed, SMTP creds, the R2 token. Connection strings are baked and
  password-free; the password is handed to the service out-of-band via
  `PGPASSWORD` / `REDIS_PASSWORD`, so it may contain any characters (no
  URL-encoding). Everything else (listen addr, TTLs, in-cluster URLs, ports,
  intervals) is baked too — change it by editing the file.
- **Postgres is external.** Server `80.66.64.227:5432`, `sslmode=require`. Each
  service has its own database `pmapa_<svc>` and logs in as the shared role
  `pmapa_user`; host, database and user are baked into its compose, only the
  password comes from `.env`. Provision and extensions:
  [`env/db/external`](../db/external). Moving one store to a different instance
  is editing the host on that single service's URL line — nothing else moves.
- **Redis is external and shared.** One managed instance
  (`generative-thorough-birthday-92146.db.redis.io:18624`, user `default`, db 0)
  serves `auth` and `stats`. Sharing it is safe because the key spaces do not
  overlap — `auth` writes `deny:*` / `dpop:*` / `fail:*`, `stats` writes
  `metric:*` — and neither service ever runs `FLUSHDB` or an unscoped
  `KEYS`/`SCAN`.
- **Passwords.** `PMAPA_DB_PASSWORD` is the one Postgres password, for the shared
  role `pmapa_user`, used by every service. `AUTH_REDIS_PASSWORD` and
  `STATS_REDIS_PASSWORD` are the same value — one instance, one password.
- **Secrets.** `AUTH_SIGNING_KEY_SEED`, the DB/Redis passwords, SMTP creds and
  the R2 API token come from `.env` (git-ignored) — inject them from your secret
  manager in a real cluster.
- **Media bytes leave the box.** `media` stores objects in Cloudflare R2 and
  serves reads from a CDN domain bound to that bucket, so image traffic never
  touches this host or the gateway. Only uploads pass through the app tier.
- **TLS.** This gateway speaks plain HTTP; terminate TLS at an outer edge (LB /
  Cloudflare) in front of it, as noted in `env/gateway/nginx.conf`.
- **No `depends_on` across composes.** Services are deployed independently and
  retry their dependencies on boot, so start order doesn't matter.
