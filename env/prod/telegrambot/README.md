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
