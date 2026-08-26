# env/gateway — internal cluster gateway (nginx)

Authenticates every request and routes to the domain services. Runs over **HTTP**;
TLS termination + real-IP hiding + geo/anycast edge are a **separate outer layer**
in front of this gateway (a later infra concern).

## What it does

- **Public auth RPCs** (`Register`/`Login`/`Refresh`/`Logout`/reset/`WhoAmI`,
  `LoginWithOidc`) pass straight through — rate-limited, with any client
  `X-User-Id` stripped.
- **Authenticated RPCs** (`ListSessions`/`RevokeSession`) go through
  `auth_request → /_verify → auth /internal/verify`. nginx injects the verified
  `X-User-Id` from the subrequest response.
- **Domain services** (`/pmapa.<travel|message|store>.vN.*`) route through one
  generic authenticated block: verify → inject `X-User-Id` → proxy to the
  upstream from the `$domain → $domain_upstream` map. Adding a service = one map
  line (+ the domain in the location regex). Unknown domains fall through to 404
  (fail-closed). Verified live via a mock upstream in the test contour.
- Forwards the **original method + URI** and client-facing **scheme + host** to
  `/internal/verify` so auth can check the DPoP `htu`/`htm` binding.

## Security invariants (why the config looks the way it does)

1. **Never trust client `X-User-Id`** — overwritten on every route (empty on
   public, verified id on authenticated). The edge + this gateway are the only
   things that may set it.
2. **Back-ends reachable only via this gateway** (network isolation) — otherwise
   invariant 1 is bypassable.
3. **DPoP htu** is rebuilt from `X-Forwarded-Proto/Host`; the **edge must set
   these authoritatively and strip client-supplied ones**. Direct/test access
   falls back to the gateway's own `$scheme`/`$host`.
4. Streaming endpoints proxy with `proxy_buffering off` + HTTP/1.1.

## Validate / run

```bash
docker run --rm -v "$PWD":/etc/nginx/gateway:ro nginx:alpine \
  nginx -t -c /etc/nginx/gateway/nginx.conf
```

Wired into the test contour compose (auth + gateway + data) as the next step.
Upstreams use a `resolver` + variable `proxy_pass` so they re-resolve at runtime
(scale auth to N replicas without reloading nginx).
