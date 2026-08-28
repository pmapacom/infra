# env/prod/gateway — cloud front door (nginx)

The **only published** service. Authenticates every request
(`auth_request` → auth `/internal/verify`), injects a trusted `X-User-Id`, and
routes by proto domain to the back-ends over the shared `pmapa` network. Runs the
same nginx config used locally and in the test contour
([env/gateway](../../gateway)), so the request path is identical everywhere.

TLS is **not** handled here — terminate it at an outer edge (LB / Cloudflare) in
front of this. The container speaks plain HTTP on the published port.

## Configuration

No `.env`, no host bind mounts — the nginx config is **baked into the image**
(`ghcr.io/pmapacom/gateway`, built from [env/gateway](../../gateway) by the infra
CI). This avoids the fragile single-file bind mount that Portainer git stacks
choke on.

- **Change the config** — edit `env/gateway/nginx.conf` / `snippets/*` and push;
  the `gateway` workflow rebuilds the image, then `docker compose pull` + redeploy
  here.
- **Public port** — `80:8080` (container listens on `:8080`). Edit the `ports`
  mapping in the compose to publish a different port to your TLS edge.

## Requirements

- The shared external `pmapa` network, with the back-end services running on it
  (the gateway resolves them by name: `auth`, `user`, …).
- An outer TLS terminator in front (production).

## Deploy — bring this up **last**, after the services

```bash
docker network create pmapa            # once per host
docker compose pull && docker compose up -d
```
