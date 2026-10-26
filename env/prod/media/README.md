# env/prod/media — cloud app tier for the media service

The **stateless** media service (image uploads → Cloudflare R2, public
`/media/{id}`), deployed from a pre-built image. Mirror of the data tier in
[env/prod/infra](../infra) — which now holds only this service's Postgres: the
bytes live in R2 and are read from the Cloudflare CDN, not from this box. No
published port; uploads arrive via the [gateway](../gateway) and reads are
redirected to the edge. Scale: `docker compose up -d --scale media=3`.

Full env-var reference: <https://github.com/pmapacom/media>.

## Environment

Three secrets are supplied at deploy time; everything else — including the CDN
host `cdn1.pmapa.com` — is a literal in `docker-compose.yml`. All three are
`${VAR:?}` — `docker compose up` refuses to start if one is missing, so there is
no silent half-configured boot.

### Supplied at deploy time

| Variable | Secret? | Purpose |
|----------|---------|---------|
| `MEDIA_POSTGRES_PASSWORD` | yes | Postgres password — host/db/user are baked. Must equal `MEDIA_POSTGRES_PASSWORD` in infra. |
| `R2_ACCESS_KEY_ID` | yes | R2 API token (R2 → Manage API Tokens), scoped to `s3-1` with *Object Read & Write*. Signs uploads. |
| `R2_SECRET_ACCESS_KEY` | yes | Same token's secret — shown once on creation. |

Pass them however your deploy does it — a shell export, `docker compose
--env-file`, or your orchestrator's secret store. Example:

bash
MEDIA_POSTGRES_PASSWORD=… R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… \
docker compose up -d

### Hardcoded in docker-compose.yml (edit the file to change)

| Variable | Value | Purpose |
|----------|-------|---------|
| `MEDIA_S3_ENDPOINT` | `https://df058166f94b385da0fae8106c5b9f00.r2.cloudflarestorage.com` | Account-scoped R2 endpoint. **Not** bucket-scoped: the dashboard shows the S3 API as `<endpoint>/s3-1`, but path-style addressing appends the bucket itself — pasting the dashboard URL would write keys under `s3-1/s3-1/`. |
| `MEDIA_S3_BUCKET` | `s3-1` | The R2 bucket. |
| `MEDIA_S3_REGION` | `auto` | R2 is single-region; `auto` is the literal SigV4 scope it expects. The ENAM location hint is not an S3 region — `enam` yields `SignatureDoesNotMatch`. |
| `MEDIA_S3_PREFIX` | `media/` | Key prefix within the bucket. Must match the path the CDN domain serves: `https://cdn1.pmapa.com/media/<id>` → key `media/<id>`. |
| `MEDIA_S3_PATH_STYLE` | `true` | Required on the `r2.cloudflarestorage.com` endpoint — it does not serve virtual-hosted bucket hosts. |
| `MEDIA_S3_PUBLIC_BASE_URL` | `https://cdn1.pmapa.com` | CDN read origin — the custom domain bound to `s3-1` (R2 → `s3-1` → Settings → Custom Domains). **Not** the apex `pmapa.com`: an R2 custom domain takes over the whole hostname, and that one serves the front end and the gateway. |
| `DATABASE_URL` | `postgres://media@media-postgres:5432/media` | Host/db/user known from infra; only the password is passed in. |
| `MEDIA_HTTP_ADDR` | `:8080` | In-network listen address. |

Uploads still pass through this service (the bucket stays write-private, only
the token can write). Reads do not: `GET /media/{id}` answers `302` to the CDN,
and new clients get the CDN URL straight from `UploadImage`.

## Requirements

- **PostgreSQL** (via `DATABASE_URL`) — see [env/prod/infra](../infra).
- **Cloudflare R2 bucket** `s3-1`, with `cdn1.pmapa.com` bound to it as a custom domain for public reads; only the token credentials arrive via `R2_*`.
- Outbound HTTPS to `*.r2.cloudflarestorage.com` — the bucket is reached over the public internet, not over `media-data`.
- Networks: `pmapa` (service RPC) + `media-data` (its Postgres) — see [env/prod/infra](../infra).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env   # or export the 3 secrets in your deploy
docker compose --env-file .env config -q   # fails naming any missing var
docker compose pull && docker compose up -d
```
