# env/prod/app — web app (Flutter web, static)

The PMapa web client, compiled to a static bundle and served by nginx. It runs
**same-origin** with the API: the [gateway](../gateway) proxies `/` to this
container and keeps `/pmapa.*` + `/media` on the back-ends, so the browser makes
no cross-origin call — **no CORS**, and DPoP's host binding stays intact.

## Configuration

No `.env`, no host bind mounts — the whole bundle is **baked into the image**
(`ghcr.io/pmapacom/app`, built from the **app repo** by its `app-image` workflow,
which checks out `app` + `proto` side by side; see `app/Dockerfile`).

- **Change the app** — push to the app repo; the `app-image` workflow rebuilds,
  then `docker compose pull` + redeploy here.
- **API origin** — baked at compile time via `--build-arg PMAPA_API_URL`
  (defaults to `https://pmapa.com`). Same-origin, so it matches the public host.
- **No published ports** — reached only through the gateway (`location /` →
  `app:8080` on the shared `pmapa` network).

## Requirements

- The shared external `pmapa` network.
- The [gateway](../gateway) running on it, with its `location /` → `app:8080`
  route (already in `env/gateway/nginx.conf`).

## Deploy

```bash
docker compose pull && docker compose up -d
```
