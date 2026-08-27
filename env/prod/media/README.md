# env/prod/media — cloud app tier for the media service

The **stateless** media service (image uploads → S3, public `/media/{id}`),
deployed from a pre-built image. Mirror of the data tier in
[env/prod/infra](../infra). No published port — the public bytes are served
via the [gateway](../gateway). Scale: `docker compose up -d --scale media=3`.

Full env-var reference: <https://github.com/pmapacom/media>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `MEDIA_POSTGRES_PASSWORD` | Postgres password — host/db/user are baked. Must equal `MEDIA_POSTGRES_PASSWORD` in infra. |
| `MINIO_ROOT_PASSWORD` | MinIO/S3 secret key — endpoint/bucket/access are baked. Must equal `MINIO_ROOT_PASSWORD` in infra. |

### Optional (in .env)

| Variable | Purpose |
|----------|---------|
| `MINIO_ROOT_USER` | MinIO/S3 access key (default `pmapa`); set only if you changed it in infra. |
| `MEDIA_S3_BUCKET` | Bucket name (default `pmapa-media`); set only if you changed it in infra. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `MEDIA_S3_ENDPOINT` | `http://minio:9000` | On-box MinIO. Set empty here to store bytes as Postgres blobs instead. |
| `MEDIA_S3_REGION` | `us-east-1` | S3 region. |
| `MEDIA_S3_PREFIX` | `media/` | Key prefix within the bucket. |
| `MEDIA_S3_PATH_STYLE` | `true` | `true` for the on-box MinIO / most providers; set `false` for AWS virtual-hosted buckets. |

## Requirements

- **PostgreSQL** (via `DATABASE_URL`) — see [env/prod/infra](../infra).
- **S3-compatible object storage** (via `MEDIA_S3_*`) — optional; Postgres-blob fallback when unset.
- Networks: `pmapa` (service RPC) + `media-data` (its store) — see [env/prod/infra](../infra).

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
```
