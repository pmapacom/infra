# env/test/auth — auth test contour

Self-contained stack to exercise the auth service exactly as it runs in the
cluster: **gateway → auth → postgres + redis** on one private network. Only the
gateway is published; auth and the data tier are unreachable from the host
(mirrors "back-ends only via the gateway").

## Run

```bash
cp .env.example .env         # already present for dev
docker compose up --build -d
docker compose ps
```

Gateway is on `http://localhost:${GATEWAY_PORT:-8088}`.

## Smoke test

```bash
B=http://localhost:8088/pmapa.auth.v1.AuthService
CT='Content-Type: application/json'

# public
curl -s -X POST $B/Register -H "$CT" \
  -d '{"email":"a@b.co","password":"hunter2pass","device":{"deviceId":"d1","label":"cli"}}'
LOG=$(curl -s -X POST $B/Login -H "$CT" \
  -d '{"email":"a@b.co","password":"hunter2pass","device":{"deviceId":"d1","label":"cli"}}')
AT=$(echo "$LOG" | python3 -c 'import sys,json;print(json.load(sys.stdin)["tokens"]["accessToken"])')

# authenticated (gateway injects the verified X-User-Id)
curl -s -X POST $B/ListSessions -H "$CT" -H "Authorization: Bearer $AT" -d '{}'
```

## What it proves

- auth_request → `/internal/verify` → verified `X-User-Id` injection;
- a forged `X-User-Id` is rejected (no token → 401) / ignored (valid token wins);
- auth + data tier are not reachable from the host.

Notes: `AUTH_REQUIRE_DPOP` is off here, so the JWT flow works without DPoP proofs
over plain curl. DPoP is exercised from the real clients (android/ios/web) next.
Tear down with `docker compose down` (add `-v` to drop the data volumes).
