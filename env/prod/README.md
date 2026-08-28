# env/prod — cloud deploy units (app tier)

One `docker-compose.yml` **per service** (the stateless app tier), plus
[`infra/`](infra) — the consolidated **data tier** for running the whole stack on
one machine:

```
        env/prod/<svc>   ── app tier    (pulls image, no state)
              │  DATABASE_URL / REDIS_URL / S3
        env/prod/infra   ── data tier   (all Postgres/Redis/MinIO on this box)
                            └ later: extract a DB → managed, repoint one URL
```

These composes **pull pre-built images** from a registry. Defaults (image, listen
addr, in-cluster URLs, ports) are baked into each compose; only the values with no
sensible default — secrets, connection strings — come from `.env`.

## What's here

| Folder | Service | Published? |
|--------|---------|------------|
| `infra/` | **data tier** — all Postgres + Redis + MinIO (on-box) | no |
| `gateway/` | nginx front door (auth_request → routes by domain) | **yes** — the only public port |
| `auth/` | auth (EdDSA JWT + DPoP + refresh) — needs Postgres + Redis | no |
| `user/` | user/profile + follow graph — needs Postgres | no |
| `travel/` | trips document store — needs Postgres | no |
| `post/` | posts/feed — needs Postgres | no |
| `store/` | goods classifieds — needs Postgres | no |
| `message/` | chat — needs Postgres | no |
| `media/` | image uploads → S3 — needs Postgres + S3 | no |
| `notification/` | email + in-app feed + push — needs Postgres + SMTP | no |
| `stats/` | metric store — needs Redis | no |
| `telegrambot/` | ops alerts (opt-in) | no |

Every service listens on `:8080` inside the network and is reachable **only via
the gateway** — none publish a host port. Cross-service calls use the service
name as DNS (`http://user:8080`, `http://stats:8080`, …), resolved by the shared
network below.

## Networks

- **`pmapa`** — one shared network for service-to-service RPC. Created once by
  hand (below); every app service + the gateway join it.
- **`<svc>-data`** — one isolated, `internal` network per data tier, **owned by
  [`infra/`](infra)**. Only that service's app tier joins it, so a service can
  reach its own store and nothing else. See [`infra/README.md`](infra/README.md).

So each app service is on **two** networks: `pmapa` (peers) + its `<svc>-data`
(its database).

## Deploy — infra first, gateway last

```bash
# 1. one-time: the shared network + a registry login
docker network create pmapa
docker login ghcr.io

# 2. data tier — brings up all DBs/Redis/MinIO and creates the <svc>-data networks
cd env/prod/infra
cp .env.example .env && $EDITOR .env      # set all passwords
docker compose up -d

# 3. each service — fill its .env (connection strings already point at infra)
cd ../auth
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
# repeat for user, travel, post, store, message, media, notification, stats

# 4. the front door, last (no .env needed)
cd ../gateway && docker compose up -d
```

Scale a stateless service horizontally (the gateway load-balances via Docker DNS):

```bash
cd env/prod/auth && docker compose up -d --scale auth=3
```

## Notes

- **Images.** The image + tag is baked into each `docker-compose.yml`
  (`image: ghcr.io/pmapacom/<svc>:latest`) — edit that line to pin a tag. Build +
  push from the repo root, e.g. `docker build -f auth/Dockerfile -t ghcr.io/pmapacom/auth:latest . && docker push ghcr.io/pmapacom/auth:latest`.
- **What goes in `.env`.** Only secrets — data-tier **passwords**, the signing
  seed, SMTP creds. Connection strings are baked (password-free); the password is
  handed to the service out-of-band via `PGPASSWORD` / `REDIS_PASSWORD`, so it may
  contain any characters. Everything else (listen addr, TTLs, in-cluster URLs,
  ports, intervals) is baked too — change it by editing the file.
- **Data tier.** On one box it's [`infra/`](infra); each service composes its URL
  from a baked container host + the password you set (`sslmode=disable`, safe
  on-host). **Extracting a DB later:** stand up a managed instance, edit the host
  + `sslmode` on that one service compose's URL line, update its password, and drop
  the store from `infra/`. The `<svc>-data` network boundary means nothing else moves.
- **Passwords must match — by name.** A service reads the **same variable name**
  as `infra/.env` (e.g. `AUTH_POSTGRES_PASSWORD`), so keeping them in sync is just
  putting the same value under the same name in both files.
- **Secrets.** `AUTH_SIGNING_KEY_SEED`, DB passwords, SMTP + S3 creds come from
  `.env` (git-ignored) — inject them from your secret manager in a real cluster.
- **TLS.** This gateway speaks plain HTTP; terminate TLS at an outer edge (LB /
  Cloudflare) in front of it, as noted in `env/gateway/nginx.conf`.
- **No `depends_on` across composes.** Services are deployed independently and
  retry their dependencies on boot, so start order doesn't matter.
