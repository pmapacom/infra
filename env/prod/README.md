# env/prod — cloud deploy units (app tier)

One `docker-compose.yml` **per service**, each deployable on its own. This is the
**stateless app tier** — the mirror image of `env/db/*` (the stateful data tier):

```
        env/prod/<svc>   ── app tier   (this dir: pulls image, N replicas, no state)
              │  DATABASE_URL / REDIS_URL
        env/db/<svc>     ── data tier  (managed Postgres/Redis in cloud)
```

Unlike the root `docker-compose.yml` (which **builds** everything into one local
stack), these composes **pull pre-built images** from a registry and take every
secret + cross-service URL from the environment. Nothing is baked in.

## What's here

| Folder | Service | Published? |
|--------|---------|------------|
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

## One shared network

All services join a single **external** overlay network named `pmapa` so they can
find each other by service name across the independent composes. Create it once
per host/cluster before bringing anything up:

```bash
docker network create pmapa          # or: docker network create -d overlay --attachable pmapa (swarm)
```

## Deploy

```bash
# 1. one-time: the shared network + a registry login
docker network create pmapa
docker login ghcr.io

# 2. per service: fill only the secrets/URLs in .env (the rest is baked in)
cd env/prod/auth
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d

# repeat for user, travel, post, store, message, media, notification, stats
# then bring up the front door last (no .env needed):
cd ../gateway && docker compose up -d
```

Scale a stateless service horizontally (the gateway load-balances via Docker DNS):

```bash
cd env/prod/auth && docker compose up -d --scale auth=3
```

## Notes

- **Images.** The image + tag is baked into each `docker-compose.yml`
  (`image: ghcr.io/pmapa/<svc>:latest`) — edit that line to pin a tag. Build +
  push from the repo root, e.g. `docker build -f auth/Dockerfile -t ghcr.io/pmapa/auth:latest . && docker push ghcr.io/pmapa/auth:latest`.
- **What goes in `.env`.** Only values with no sensible default — secrets,
  `DATABASE_URL`/`REDIS_URL`, S3 + SMTP config. Everything else (listen addr,
  TTLs, in-cluster service URLs, ports, intervals) is baked into the compose;
  change it by editing the file, not the environment.
- **Data tier.** `DATABASE_URL` / `REDIS_URL` must point at **managed** Postgres/
  Redis (use `sslmode=require`). Do not run `env/db/*` per app replica — those are
  a single data host, one per logical database.
- **Secrets.** `AUTH_SIGNING_KEY_SEED`, DB passwords, SMTP + S3 creds come from
  `.env` (git-ignored) — inject them from your secret manager in a real cluster.
- **TLS.** This gateway speaks plain HTTP; terminate TLS at an outer edge (LB /
  Cloudflare) in front of it, as noted in `env/gateway/nginx.conf`.
- **No `depends_on` across composes.** Services are deployed independently and
  retry their dependencies on boot, so start order doesn't matter.
