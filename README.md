# PMapa

> Plan it. Map it. Share it.

A travel-journal app: a Flutter client (`app/`) over a Go + Connect-RPC
microservice backend, fronted by an nginx gateway that verifies tokens and is the
single front door for every service.

📦 **Infra repo:** <https://github.com/pmapacom/infra> — the public deploy units
(gateway config, per-service data tiers, cloud composes, test contours).

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
| `media/` | Media service — image uploads → S3/MinIO + public `/media/{id}` |
| `notification/` | Notification service — outbound email (SMTP) + in-app activity feed + push tokens/prefs |
| `telegrambot/` | Ops bot — polls `/readyz`/`/internal/logz`/`/internal/stats`, alerts + reports to Telegram (opt-in `--profile ops`) |
| `svckit/` | Shared service toolkit — server/config/identity + Postgres helpers |
| `proto/` | Protobuf schemas + generated Go (`proto/gen/go`) and Dart (`proto/gen/dart`) |
| `env/` | Deploy units — gateway config, per-service data tiers, test contours |
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
      auth-postgres     auth-redis     user-postgres
        :5432             :6379           :5433          ← published to 127.0.0.1
      (revocation      (denylist +      (profiles)         for local inspection only
       + accounts)      rate limits)
```

Invariants kept identical to production:

- **Only the gateway is the front door.** `auth` and `user` publish no ports; the
  gateway verifies the token and injects a trusted `X-User-Id` — a forged header
  from the client is stripped (verify: a call with `-H 'X-User-Id: forged'` and no
  token returns `401`).
- **Data tier is the single source of truth**, on named volumes so local data
  survives restarts. Postgres/Redis bind `127.0.0.1` only — dev-only, so you can
  `psql -h localhost -p 5432 -U auth` / `redis-cli -p 6379` to inspect state.

### Everyday commands

```bash
docker compose logs -f auth   # tail a service
docker compose up -d --build auth   # rebuild + restart one service
docker compose down           # stop (named volumes keep their data)
docker compose down -v        # stop and wipe all data
```

All nine services (`auth`, `user`, `travel`, `post`, `store`, `stats`,
`message`, `media`, `notification`) run in the stack; each has its own data tier
(Postgres per domain; `stats` uses Redis; `auth` adds Redis). The gateway routes
the versioned **client** domains (`pmapa.<domain>.v1`) plus the public `/media/`
bytes location. **Internal** s2s contracts under `pmapa.api.*` (unversioned) are
never routed — `pmapa.api.purge` (`PurgeUser`), `pmapa.api.email` (`SendEmail`),
`pmapa.api.notify` (`Notify`) and the whole `pmapa.api.stats` metric store are
404 from outside, reachable only inside the cluster. `notification` still exposes
its **read/prefs RPCs** through the gateway (auth allowlist).

Two dev-infrastructure containers make everything testable with zero external
accounts:

- **MinIO** — local S3 for the media service (bucket auto-created).
  Console: http://localhost:9001, `minioadmin`/`minioadmin`.
- **Mailpit** — catches all outgoing email (password resets).
  Inbox: http://localhost:8025.

### Isolated stacks

The composes under `env/` remain for narrower scenarios — a single service's data
tier (`env/db/*`) or a self-contained CI test contour (`env/test/*`). They bind the
same host ports as the root stack, so bring the root stack down before running one.
