# kuma-wa-bridge

Tiny webhook bridge: [Uptime Kuma](https://github.com/louislam/uptime-kuma) → WhatsApp via [`wa_hack_cli`](https://github.com/grindsa) (`simple_send`).

## Layout on the Pi

| Path | Role |
|------|------|
| `/srv/stacks/kuma-wa-bridge` | compose + image build |
| `.env` next to compose | `WA_*` and `WEBHOOK_TOKEN` |

## Quick start

```bash
cp .env.example .env
# set WA_SRV, WA_PORT, WA_RECIPIENT, WEBHOOK_TOKEN

docker network create pi-monitor   # once
docker compose up -d --build
curl -s http://127.0.0.1:8089/health
```

Attach Uptime Kuma to the same external network `pi-monitor`, then add a **Webhook** notification:

- URL: `http://kuma-wa-bridge:8080/webhook`
- Method: `POST`
- Body: default JSON
- Headers: `{"Authorization": "Bearer <WEBHOOK_TOKEN>"}`

## Endpoints

- `GET /health` — config present
- `POST /webhook` — Bearer token required; forwards Kuma `msg` (or a short fallback) via `wa_hack_cli.simple_send`
