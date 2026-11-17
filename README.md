# kuma-wa-bridge

Tiny webhook bridge: [Uptime Kuma](https://github.com/louislam/uptime-kuma) → WhatsApp via `wa_hack_cli.simple_send`.

Compose lives in this repo; **all runtime config is in `.env`** (never committed). The Docker image is **built locally on the Pi** (no registry / no GHA publish).

## Provision on the Pi

```bash
sudo git clone https://github.com/grindsa/kuma-wa-bridge.git /srv/stacks/kuma-wa-bridge
cd /srv/stacks/kuma-wa-bridge
cp .env.example .env
# edit WA_SRV, WA_PORT, WA_RECIPIENT, WEBHOOK_TOKEN

sudo docker network create pi-monitor 2>/dev/null || true
sudo docker compose up -d --build
curl -s http://127.0.0.1:8089/health
```

## Deploy / upgrade

From the checkout on the Pi (keeps your local `.env`):

```bash
cd /srv/stacks/kuma-wa-bridge
./deploy.sh
```

The script `git pull --ff-only`s the current branch, rebuilds the image on the Pi, recreates the container, and hits `/health`. It aborts if `.env` is missing or the working tree has local changes.

## `.env` keys

| Variable | Purpose |
|----------|---------|
| `WA_SRV` / `WA_PORT` | wa_hack daemon |
| `WA_RECIPIENT` | WhatsApp destination (digits, no `+`) |
| `WEBHOOK_TOKEN` | Bearer token Kuma must send |
| `BIND_HOST` / `HOST_PORT` | host publish (default `127.0.0.1:8089`) |
| `IMAGE` | local image tag (default `kuma-wa-bridge:latest`) |
| `NETWORK_NAME` | Docker network (default `pi-monitor`) |

## Kuma

Attach Uptime Kuma to external network `pi-monitor`, then Webhook:

- URL: `http://kuma-wa-bridge:8080/webhook`
- Method: `POST`
- Body: default JSON
- Headers: `{"Authorization": "Bearer <WEBHOOK_TOKEN>"}`

## Endpoints

- `GET /health`
- `POST /webhook` (Bearer required)
