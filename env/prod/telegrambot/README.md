# env/prod/telegrambot — cloud app tier for the ops bot

The **stateless** ops bot: polls every service's `/readyz`, `/internal/logz` and
`/internal/stats`, alerts to Telegram on a down service or new WARN+ logs, and
posts a periodic status+stats report. Optional; deploy **one** instance (it holds
no shared state). No data tier.

Full env-var reference: <https://github.com/pmapacom/telegrambot>.

## Environment

Copy `.env.example` → `.env` and fill it. **Must set** vars are `${VAR:?}` — boot
fails (`os.Exit(1)`) if unset.

### Must set

| Variable | Purpose |
|----------|---------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token. |
| `TELEGRAM_CHAT_ID` | Target chat id for alerts + reports. |

### Optional (in .env)

| Variable | Purpose |
|----------|---------|
| `TELEGRAM_API_BASE` | **Fallback** Bot API base. The bot tries `api.telegram.org` first and only fails over to this when the direct endpoint is unreachable — set it to a Cloudflare Worker URL when your host blocks Telegram (see below). Unset ⇒ direct only. |

### Baked into docker-compose.yml (edit the file to change)

| Variable | Default | Purpose |
|----------|---------|---------|
| `TELEGRAM_SERVICES` | `auth=…,user=…,…` (all 9 services) | Comma-separated `name=url` set to monitor. |
| `TELEGRAM_POLL_INTERVAL` | `30s` | How often to poll `/readyz` + logs. |
| `TELEGRAM_REPORT_INTERVAL` | `24h` | Status+stats report cadence. |
| `TELEGRAM_ALERT_COOLDOWN` | `5m` | Min gap between error alerts per service. |

## Requirements

- Network access from the `pmapa` network to each monitored service's
  `/readyz`, `/internal/logz`, `/internal/stats`.
- No database.
- The shared external `pmapa` network.

## Deploy

```bash
docker network create pmapa            # once per host
cp .env.example .env && $EDITOR .env
docker compose pull && docker compose up -d
docker compose logs -f telegrambot
```

## Telegram blocked from your host? (Cloudflare Worker — no extra container)

If the server can't reach `api.telegram.org` (`dial tcp … i/o timeout`, common
where Telegram is region-blocked), route the Bot API through a **Cloudflare
Worker** — serverless, free tier, nothing to run on your box.

1. Cloudflare dashboard → **Workers & Pages** → **Create** → **Worker**. Give it
   a name (e.g. `pmapa-tg`), **Deploy**.
2. **Edit code** → paste [`cloudflare-worker.js`](cloudflare-worker.js) → **Deploy**.
   You now have a URL like `https://pmapa-tg.<subdomain>.workers.dev`.
3. Test it (should return Telegram JSON `{"ok":true,...}`):
   `curl https://pmapa-tg.<subdomain>.workers.dev/bot<token>/getMe`
4. Set it in this stack's `.env` and redeploy:
   `TELEGRAM_API_BASE=https://pmapa-tg.<subdomain>.workers.dev`
   `docker compose up -d`

The Worker forwards every call unchanged to Telegram (long-poll included), so the
bot behaves identically — it just exits through Cloudflare's network. The token
only ever travels in the path, and the Worker refuses non-`/bot` paths so it
isn't a generic open proxy.
