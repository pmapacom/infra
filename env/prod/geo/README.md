# geo — app tier

Public place dictionary: ISO 3166-1 countries + the GeoNames `cities500` tier,
served over Connect-RPC as `pmapa.geo.v1.GeoService`.

```bash
docker compose pull && docker compose up -d
```

**No `.env`.** This service has no database, no cache and no secrets. Both
datasets are baked into the image, so a container is disposable and boots in
about a second.

**Scaling.** Stateless and read-only, so scale freely; the gateway
load-balances via Docker DNS:

```bash
docker compose up -d --scale geo=3
```

Each replica holds the dictionary in memory (~60 MB resident), so prefer a
couple of replicas over many.

## Gateway route — public on purpose

`/pmapa.geo.v1.GeoService/` is routed **without** `auth_request`. A place
dictionary is not user data, and the country/city pickers must work before
sign-in (onboarding, offline mode) and be crawlable on the public `/explore`
pages. The gateway still strips any client-supplied `X-User-Id`.

That route lives in `env/gateway/nginx.conf` and is baked into the gateway
image, so it only appears after the gateway image is rebuilt (infra CI does that
on any push touching `env/gateway/**`) and `env/prod/gateway` is redeployed.

The upstream is a resolver variable, so nginx starts whether or not `geo` is
running — the route simply answers 502 until it is. Starting `geo` first just
avoids that window.

## Updating the city dump

The dump is part of the image, not a volume. To refresh it, regenerate
`data/cities500.txt` in the `geo` repo, push, and redeploy — see that repo's
README for the one-liner.
