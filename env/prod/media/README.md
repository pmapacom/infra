# env/prod/media — cloud app tier for the media service

The **stateless** media service (image uploads → S3, public `/media/{id}`),
deployed from a pre-built image. Mirror of the data tier in
[env/db/media](../../db/media). No published port — the public bytes are served
via the [gateway](../gateway). Scale: `docker compose up -d --scale media=3`.

Full env-var reference: <https://github.com/pmapacom/media>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Managed Postgres URL (metadata + optional blob fallback; `sslmode=require`). |
| `MEDIA_S3_ENDPOINT` | S3-compatible endpoint. Set empty (`MEDIA_S3_ENDPOINT=`) to store bytes as Postgres blobs instead. |
| `MEDIA_S3_BUCKET` | Bucket name. |
| `MEDIA_S3_ACCESS_KEY` / `MEDIA_S3_SECRET_KEY` | S3 credentials. |
| `MEDIA_S3_REGION` | S3 region (provider-specific; falls back to `us-east-1` if unset). |

> S3 is used only when endpoint + bucket + access + secret are **all** set;
> otherwise the service falls back to storing image bytes in Postgres.

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `MEDIA_S3_PREFIX` | `media/` | Key prefix within the bucket. |
| `MEDIA_S3_PATH_STYLE` | `false` | `true` for MinIO/most providers; `false` for AWS virtual-hosted buckets. |

## Requirements

- Managed **PostgreSQL** (via `DATABASE_URL`) — see [env/db/media](../../db/media).
- **S3-compatible object storage** (via `MEDIA_S3_*`) — optional; Postgres-blob fallback when unset.
- The shared external `pmapa` network.

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
