# kuma-wa-bridge

Tiny webhook bridge: [Uptime Kuma](https://github.com/louislam/uptime-kuma) → WhatsApp via `wa_hack_cli.simple_send`.

Compose lives in this repo; **all runtime config is in `.env`** (never committed).

## Provision on the Pi

### Option A — compose + prebuilt image (preferred)

After the image is published to GHCR (`ghcr.io/grindsa/kuma-wa-bridge`):

```bash
sudo mkdir -p /srv/stacks/kuma-wa-bridge
cd /srv/stacks/kuma-wa-bridge

# private repo: use gh (or git clone) to fetch compose + env example
gh api repos/grindsa/kuma-wa-bridge/contents/docker-compose.yml \
  --jq .content | base64 -d > docker-compose.yml
gh api repos/grindsa/kuma-wa-bridge/contents/.env.example \
  --jq .content | base64 -d > .env.example

cp .env.example .env
# edit WA_SRV, WA_PORT, WA_RECIPIENT, WEBHOOK_TOKEN

# pull private GHCR image (once per host)
echo "$GITHUB_TOKEN" | sudo docker login ghcr.io -u USERNAME --password-stdin

sudo docker network create pi-monitor 2>/dev/null || true
sudo docker compose pull
sudo docker compose up -d
curl -s http://127.0.0.1:8089/health
```

### Option B — clone and build on the Pi

```bash
sudo git clone https://github.com/grindsa/kuma-wa-bridge.git /srv/stacks/kuma-wa-bridge
cd /srv/stacks/kuma-wa-bridge
cp .env.example .env
# edit .env

sudo docker network create pi-monitor 2>/dev/null || true
sudo docker compose up -d --build
```

## Upgrade

From the checkout on the Pi (keeps your local `.env`):

```bash
cd /srv/stacks/kuma-wa-bridge
./upgrade.sh
```

The script `git pull --ff-only`s the current branch, pulls/rebuilds the image, recreates the container, and hits `/health`. It aborts if `.env` is missing or the working tree has local changes.

## `.env` keys

| Variable | Purpose |
|----------|---------|
| `WA_SRV` / `WA_PORT` | wa_hack daemon |
| `WA_RECIPIENT` | WhatsApp destination (digits, no `+`) |
| `WEBHOOK_TOKEN` | Bearer token Kuma must send |
| `BIND_HOST` / `HOST_PORT` | host publish (default `127.0.0.1:8089`) |
| `IMAGE` | override image (default GHCR `latest`) |
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
