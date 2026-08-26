# env/prod/gateway — cloud front door (nginx)

The **only published** service. Authenticates every request
(`auth_request` → auth `/internal/verify`), injects a trusted `X-User-Id`, and
routes by proto domain to the back-ends over the shared `pmapa` network. Mounts
the same nginx config used locally and in the test contour
([env/gateway](../../gateway)), so the request path is identical everywhere.

TLS is **not** handled here — terminate it at an outer edge (LB / Cloudflare) in
front of this. The container speaks plain HTTP on the published port.

## Environment

Copy `.env.example` → `.env` (optional — a default is provided).

| Variable | Default | Purpose |
|----------|---------|---------|
| `GATEWAY_PORT` | `80` | Public HTTP port your TLS edge forwards to (container listens on `:8080`). |

The nginx config itself is mounted read-only from `../../gateway/` — edit it
there, not here.

## Requirements

- The shared external `pmapa` network, with the back-end services running on it
  (the gateway resolves them by name: `auth`, `user`, …).
- An outer TLS terminator in front (production).

## Deploy — bring this up **last**, after the services

```bash
docker network create pmapa            # once per host
cp .env.example .env
docker compose up -d
```
