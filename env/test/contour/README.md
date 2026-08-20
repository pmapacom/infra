# env/test/contour — full app↔auth↔user contour

Self-contained stack exercising the real request path exactly as it runs in the
cluster: **gateway → auth (verify) → user**, plus auth's and user's own data
tiers, on one private network. Only the gateway is published; every service and
database is unreachable from the host (mirrors "back-ends only via the gateway").

```
             ┌── gateway (nginx, :8088) ──┐
 client ───► │  auth_request → /_verify   │
             │        │ (auth)            │
             │        ▼ inject X-User-Id  │
             │  route by domain ──► user  │
             └────────────────────────────┘
   auth ─► auth-postgres + auth-redis     user ─► user-postgres
```

## Run

```bash
cp .env.example .env            # already present for dev
docker compose up --build -d
docker compose ps               # all healthy; only gateway published
```

Gateway on `http://localhost:${GATEWAY_PORT:-8088}`.

## Integration test (app → auth → user)

The Dart contour test drives the **real** `AuthController` + `UserClient` through
the gateway (device DPoP key, token orchestration, gateway X-User-Id injection):

```bash
cd ../../../app
flutter test contour_test/user_contour_test.dart
# override the gateway with --dart-define=CONTOUR_URL=...
```

It self-skips when the contour is not reachable, so it is safe to leave in CI
without the stack up. `flutter test` (default) never runs it — it lives in
`contour_test/`, not `test/`.

## What it proves

- app registers via auth, then calls the **user** service through the gateway;
- the gateway verifies the token and injects a trusted `X-User-Id` — the user
  service provisions/reads the profile for exactly that id;
- the follow graph works across two devices/users end to end;
- a call with no token (or a forged `X-User-Id`) is rejected — back-ends are not
  reachable directly and client identity is never trusted.

Tear down with `docker compose down` (add `-v` to drop the data volumes).
