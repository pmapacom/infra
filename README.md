# PMapa

> Plan it. Map it. Share it.

A travel-journal app: a Flutter client (`app/`) over a Go + Connect-RPC
microservice backend, fronted by an nginx gateway that verifies tokens and is the
single front door for every service.

📦 **Infra repo:** <https://github.com/pmapacom/infra> — the public deploy units
(gateway config, cloud composes, test contours).

## Repository layout

| Path | What |
|------|------|
| `app/` | Flutter client (offline-first; see [`DOC/app`](DOC/app/README.md)) |
| `auth/` | Auth service — EdDSA JWT + DPoP + rotating device-bound refresh |
| `user/` | User/profile service — public profile + follow graph + discovery |
| `travel/` | Travel service — the user's trips (opaque client-owned documents) |
| `post/` | Post service — posts, likes/saves/comments, reviews, feed (cursor), own-stats |
| `message/` | Message service — 1:1/group chat, governance, live `Subscribe` stream, search, retention |
| `store/` | Store service — goods classifieds + favourites |
| `stats/` | Stats service — generic Redis named-metric store (`Get`/`BatchGet`/`List`) |
| `media/` | Media service — image uploads → S3 (Cloudflare R2 in prod, MinIO locally) + public `/media/{id}`, read from the CDN when configured |
| `notification/` | Notification service — outbound email (SMTP) + in-app activity feed + push tokens/prefs |
| `telegrambot/` | Ops bot — polls `/readyz`/`/internal/logz`/`/internal/stats`, alerts + reports to Telegram (opt-in `--profile ops`) |
| `svckit/` | Shared service toolkit — server/config/identity + Postgres helpers |
| `proto/` | Protobuf schemas + generated Go (`proto/gen/go`) and Dart (`proto/gen/dart`) |
| `env/` | Deploy units — gateway config, external-store provisioning, cloud composes, test contours |
| `DOC/` | Architecture docs ([backend](DOC/backend/README.md) · [app](DOC/app/README.md)) |
| `docker-compose.yml` | **Full local dev stack** (see below) |

## Local run

One command brings up the entire backend exactly as it runs in the cluster:

```bash
cp .env.example .env          # a ready dev .env is already committed
docker compose up --build -d  # build Go images + start everything
docker compose ps             # wait until all healthy
```

The gateway is then on **`http://localhost:8088`**. Point the app at it:

```bash
cd app
flutter run --dart-define=PMAPA_API_URL=http://localhost:8088
```

### Stack

```
                            host :8088
                                │
                 ┌──────────────▼───────────────────────────┐
                 │  gateway (nginx)                          │
   Flutter app ─►│   1. auth_request ─► auth /internal/verify│
                 │   2. strip client X-User-Id, inject trusted│
                 │   3. route by proto domain                 │
                 └───┬──────────────────────┬─────────────────┘
                     │ pmapa.auth.*          │ pmapa.user.* (travel/message/store…)
                     ▼                       ▼
                  ┌──────┐               ┌──────┐
                  │ auth │               │ user │      (no published ports —
                  └──┬───┘               └──┬───┘       reachable only via gateway)
             ┌───────┴───────┐              │
             ▼               ▼              ▼
             │               │              │
             ▼               ▼              ▼
      external Postgres 80.66.64.227:5432 (pmapa_<svc>)
      external managed Redis (auth denylist + stats, db 0)
                     ↑ no containers, no volumes — the data
                       outlives `docker compose down -v`
```

Invariants kept identical to production:

- **Only the gateway is the front door.** `auth` and `user` publish no ports; the
  gateway verifies the token and injects a trusted `X-User-Id` — a forged header
  from the client is stripped (verify: a call with `-H 'X-User-Id: forged'` and no
  token returns `401`).
- **The stores are external, not containers.** Postgres lives on
  `80.66.64.227:5432` (one database **and** one login role per service, both
  named `pmapa_<svc>`) and Redis is a managed instance — see
  [`env/db/external`](env/db/external) for provisioning. Nothing stateful runs
  in this compose, so local data survives even `docker compose down -v`.

### Everyday commands

```bash
docker compose logs -f auth   # tail a service
docker compose up -d --build auth   # rebuild + restart one service
docker compose down           # stop (external stores keep their data)
docker compose down -v        # stop and wipe the MinIO volume only
```

All nine services (`auth`, `user`, `travel`, `post`, `store`, `stats`,
`message`, `media`, `notification`) run in the stack; each owns its own external
database `pmapa_<svc>` (`stats` uses Redis only; `auth` adds Redis). The gateway routes
the versioned **client** domains (`pmapa.<domain>.v1`) plus the public `/media/`
bytes location. **Internal** s2s contracts under `pmapa.api.*` (unversioned) are
never routed — `pmapa.api.purge` (`PurgeUser`), `pmapa.api.email` (`SendEmail`),
`pmapa.api.notify` (`Notify`) and the whole `pmapa.api.stats` metric store are
404 from outside, reachable only inside the cluster. `notification` still exposes
its **read/prefs RPCs** through the gateway (auth allowlist).

Two dev-infrastructure containers make everything testable with zero external
accounts:

- **MinIO** — local S3 for the media service (bucket auto-created), the dev
  stand-in for Cloudflare R2. Console: http://localhost:9001,
  `minioadmin`/`minioadmin`. It is not a public origin, so `MEDIA_S3_PUBLIC_BASE_URL`
  stays empty locally and the service proxies reads as before.
- **Mailpit** — catches all outgoing email (password resets).
  Inbox: http://localhost:8025.

### Isolated stacks

The composes under `env/` remain for narrower scenarios — a single service's
store (`env/db/*`) or a self-contained CI test contour (`env/test/*`). They bind
the same host ports as the root stack, so bring the root stack down before
running one. Cloud deploy units live in [`env/prod`](env/prod) — app tier only,
no data tier.
