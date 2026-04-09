# Home Server Auto-Deploy Setup

This repo is set up so you only do SSH/manual setup once on a fresh Raspberry Pi, then future deploys happen on every push to `main`.

Your GitHub repo name (`home_server`) and local folder name (`homelab` or `~/homelab`) do not need to match.

## Profiles

Optional public-facing pieces are disabled unless you turn them on in `~/homelab/.env`:

- empty `COMPOSE_PROFILES` = local-only stack
- `COMPOSE_PROFILES=local-ollama` = run Ollama inside Docker on the Pi
- `COMPOSE_PROFILES=public-game` = enable Playit for games like Minecraft
- `COMPOSE_PROFILES=public-http` = enable Traefik for host-based local HTTP routing behind your host Cloudflare tunnel
- `COMPOSE_PROFILES=public-game,public-http` = games + Traefik router
- `COMPOSE_PROFILES=local-ollama,public-game,public-http` = full public stack with Docker Ollama and host Cloudflare tunnel

## Public HTTP Model

HTTP apps should use dedicated hostnames at the site root:

- `https://drive.example.com`
- `https://chat.example.com`
- `https://imggen.example.com`

This is more scalable than path prefixes because apps like Open WebUI, Nextcloud,
and many admin dashboards expect to live at `/` on their own hostname.

Your host Cloudflare Tunnel should expose one local service:

- `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`

Traefik then routes each hostname to the right container.
One host-managed Cloudflare Tunnel can publish many hostnames, all pointing at the same local Traefik service.
You do not need one separate tunnel per subdomain.

Recommended ingress strategy for this repo:

- web apps such as Open WebUI: Cloudflare Tunnel + Traefik + one subdomain per app
- Nextcloud AIO: use its own built-in stack instead of Traefik labels or custom reverse-proxy config
- game traffic such as Minecraft: Playit on the native game port
- local-only backends such as Ollama: keep private unless you intentionally expose the HTTP API

Path-based URLs like `https://yourdomain.com/minecraft` are not appropriate for Minecraft, and path-based reverse proxying is a poor fit for apps like Nextcloud and Open WebUI. A hybrid setup is the stable option: subdomains for HTTP apps, native TCP forwarding for Minecraft.

When you use a Quick Tunnel instead of an owned-domain Cloudflare tunnel, `cloudflared` runs on the Pi host as a `systemd` service and points at:

- one app directly, such as `http://127.0.0.1:3001` for Open WebUI

## Supported Services

Current built-in services in `docker-compose.yml`:

- `minecraft`: Java server on TCP `25565`; best exposed with Playit, not Cloudflare HTTP
- `ollama`: local LLM backend on `11434`; usually keep private and let Open WebUI talk to it
- `openwebui`: web UI for Ollama and cloud AI providers; recommended public hostname `chat.example.com`
- `nextcloud`: Nextcloud All-in-One with bundled PostgreSQL; recommended public hostname `drive.example.com`
- `admin-control`: protected service control panel; recommended public hostname `admin.example.com`
- `traefik`: local HTTP router for subdomain-based routing; usually keep private and use it behind Cloudflare Tunnel
- `playit`: public TCP/UDP agent for games like Minecraft

Recommended subdomain map with `example.com` placeholders:

- `chat.example.com` -> Open WebUI
- `drive.example.com` -> Nextcloud AIO
- `admin.example.com` -> Admin Control
- `api.example.com` -> optional future Ollama API exposure if you really want it public
- no subdomain needed for `minecraft`; expose through Playit instead
- no subdomain needed for `traefik`; keep local on `127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- no subdomain needed for `playit`; it is a transport service, not a user-facing app

Recommended starting point for your homelab:

- `chat.example.com` -> Open WebUI
- `drive.example.com` -> Nextcloud AIO
- `admin.example.com` -> Admin Control
- keep Ollama private at first
- keep Traefik dashboard private at first
- use Playit for Minecraft
- keep port `80` free on the Pi if you want to use AIO without a reverse proxy

## Cloudflare Setup Map

Use one host-managed Cloudflare Tunnel, not one tunnel per subdomain.

Inside Cloudflare Zero Trust -> Tunnels -> your tunnel -> Public Hostname, create:

- `chat.yourdomain.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- `drive.yourdomain.com` -> Nextcloud AIO directly; do not route it through the repo Traefik setup
- `admin.yourdomain.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- `api.yourdomain.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`

Do not create Cloudflare HTTP tunnel hostnames for:

- `minecraft.yourdomain.com` if you mean actual Minecraft gameplay
- Traefik dashboard unless you intentionally secure and expose it later
- Ollama unless you explicitly want the raw API reachable from the internet

For your current intended setup, the Cloudflare public hostnames to add are:

- `chat.example.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- `drive.example.com` -> Nextcloud AIO directly
- `admin.example.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`

If you want to keep it minimal for first boot, create only:

- `chat.example.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`

and add Nextcloud AIO after Open WebUI is stable.

## What Auto-Updates

On push to `main`, GitHub Actions (self-hosted runner on the Pi) will:

1. Pull latest git changes into `~/homelab`
2. Pull available container images
3. Rebuild local custom services in `services/*`
4. Run `docker compose up -d --build --remove-orphans` for the profiles enabled in `.env`

This means:

- new services are created automatically on push
- changed services are rebuilt and restarted automatically on push
- unchanged services normally stay up
- services with auto-start disabled in Admin Control are stopped again after deploy reconciliation

## What Does Not Auto-Update

- `~/homelab/.env` values and secrets (you manage these manually)
- Cloudflare Zero Trust dashboard settings for your host tunnel (only if you use `public-http`)
- DNS records outside your wildcard setup

## One-Time Setup (Fresh Pi)

Run once on the Raspberry Pi:

```bash
git clone https://github.com/samarthpusalkar/home_server.git ~/homelab
cd ~/homelab
bash scripts/bootstrap_fresh_pi.sh
```

Then edit:

```bash
nano ~/homelab/.env
```

Set these base values:

- `WEBUI_SECRET_KEY`
- `OLLAMA_BASE_URL`
- `ADMIN_USERNAME`
- `ADMIN_PASSWORD_HASH`
- `ADMIN_SESSION_SECRET`

Set these only if you enable `public-http`:

- `PUBLIC_APP_SCHEME`
- `ADMIN_PUBLIC_HOST`
- `ADMIN_PUBLIC_URL`
- `OPENWEBUI_PUBLIC_HOST`
- `OPENWEBUI_PUBLIC_URL`
- `OPENWEBUI_CORS_ALLOW_ORIGIN`
- `NEXTCLOUD_PUBLIC_HOST`
- `NEXTCLOUD_PUBLIC_URL`

The committed `.env.example` uses `example.com` placeholders only. Put your real domain only in your local `.env`.

If you only want Minecraft/public game access for now, you can leave Cloudflare values alone and set:

```bash
COMPOSE_PROFILES=public-game
```

## Ollama Mode

This repo now defaults to using host-installed Ollama on the Raspberry Pi:

- `OLLAMA_BASE_URL=http://host.docker.internal:11434`

That means:

- your existing host Ollama install is reused
- any models already pulled on the Pi host are reused
- if you signed in to Ollama on the Pi host, Open WebUI talks to that same Ollama instance

If you actually want Ollama inside Docker instead, enable:

```bash
COMPOSE_PROFILES=local-ollama
```

and set:

```bash
OLLAMA_BASE_URL=http://ollama:11434
```

If you do not want Ollama at all and only want cloud AI providers, keep `local-ollama` disabled and configure those providers inside Open WebUI instead.

## One-Time Cloudflare Tunnel Setup

This section is optional. Skip it unless you own a domain and want a scalable public setup for apps such as Nextcloud or Open WebUI.

In Cloudflare Zero Trust -> Tunnels -> your host tunnel -> Public Hostname, create one hostname per app and point each one to:

- Service: `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`

Examples:

- `chat.yourdomain.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- `drive.yourdomain.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- `imggen.yourdomain.com` -> `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`

After this is added, every new HTTP service can be exposed by adding a hostname rule in Traefik.

Example mapping if your domain is `example.com`:

- `chat.example.com` -> `http://traefik:80` for Open WebUI
- `drive.example.com` -> handled separately by Nextcloud AIO
- `api.example.com` -> `http://traefik:80` only if you later choose to publish Ollama or another HTTP API

Then set matching values in `~/homelab/.env`, for example:

```bash
COMPOSE_PROFILES=local-ollama,public-game,public-http

OPENWEBUI_PUBLIC_HOST=chat.example.com
OPENWEBUI_PUBLIC_URL=https://chat.example.com
OPENWEBUI_CORS_ALLOW_ORIGIN=https://chat.example.com;http://127.0.0.1:3001;http://localhost:3001

NEXTCLOUD_PUBLIC_HOST=drive.example.com
NEXTCLOUD_PUBLIC_URL=https://drive.example.com
```

For Minecraft, keep using the `minecraft` container on port `25565` and expose it with the `public-game` Playit profile rather than Cloudflare HTTP routing.

## Bring-Up Checklist

1. Copy `.env.example` to `.env` on the Pi.
2. Set your secrets:
   - `WEBUI_SECRET_KEY`
   - `PLAYIT_SECRET_KEY` if using Minecraft public access
3. Set profiles based on what you want running:
   - `COMPOSE_PROFILES=local-ollama,public-http` for Open WebUI + Nextcloud + Docker Ollama
   - add `public-game` if you also want Minecraft via Playit
4. Set app hostnames in `.env`:
   - `OPENWEBUI_PUBLIC_HOST=chat.yourdomain.com`
   - `OPENWEBUI_PUBLIC_URL=https://chat.yourdomain.com`
   - `OPENWEBUI_CORS_ALLOW_ORIGIN=https://chat.yourdomain.com;http://127.0.0.1:3001;http://localhost:3001`
   - `NEXTCLOUD_PUBLIC_HOST=drive.yourdomain.com`
   - `NEXTCLOUD_PUBLIC_URL=https://drive.yourdomain.com`
5. If using Docker Ollama, set:
   - `OLLAMA_BASE_URL=http://ollama:11434`
6. For Nextcloud AIO, complete first-time setup through `https://<pi-ip>:8081`. AIO bundles PostgreSQL, so you should not need to choose SQLite.
7. In Cloudflare Tunnel, point `chat.yourdomain.com` to `http://traefik:80`. Configure `drive.yourdomain.com` separately for the AIO deployment you choose.
8. Run:

```bash
cd ~/homelab
bash scripts/deploy.sh
```

## Debugging Guide

Work from inside outward: container -> local port -> Traefik -> host Cloudflare tunnel -> public hostname.

If your Pi does not support `docker compose`, use `docker-compose` for the manual commands below. The repo scripts already auto-detect both variants.

### 1. Check container state

```bash
cd ~/homelab
docker compose --env-file .env ps
docker compose --env-file .env logs -f openwebui
docker compose --env-file .env logs -f nextcloud
docker compose --env-file .env logs -f playit
docker compose --env-file .env logs -f ollama
```

### 2. Check direct local app reachability on the Pi

```bash
curl -I http://127.0.0.1:3001
curl -kI https://127.0.0.1:8081
curl -I http://127.0.0.1:11434
```

Expected meaning:

- `3001` responds = Open WebUI container is up
- `8081` responds = Nextcloud AIO setup interface is up
- `11434` responds = Ollama is reachable

### 3. Check Traefik routing before blaming Cloudflare

Run these on the Pi:

```bash
curl -I -H 'Host: chat.yourdomain.com' http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}
```

Expected meaning:

- success here but failure on the public hostname usually means Cloudflare Tunnel hostname config is wrong
- failure here means the problem is local Traefik labels, missing profiles, or missing env values

### 4. Check the host Cloudflare Tunnel itself

```bash
systemctl status cloudflared
journalctl -u cloudflared -n 100 --no-pager
```

Things to verify:

- the host `cloudflared` service is running
- `chat` and `admin` hostnames point to `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- `drive` should not use the old repo-level Nextcloud reverse-proxy wiring
- the hostname in Cloudflare exactly matches the hostname in your `.env`

### 5. Check common app-specific issues

Open WebUI:

- wrong `OPENWEBUI_PUBLIC_URL` can cause odd redirects or login/session issues
- wrong `OPENWEBUI_CORS_ALLOW_ORIGIN` can cause browser-side API failures
- wrong `OLLAMA_BASE_URL` means the UI loads but models/chat fail

Nextcloud:

- AIO includes PostgreSQL, so you should not need to choose SQLite during the AIO-managed setup path
- use `https://<pi-ip>:8081` for the AIO interface, not your public domain
- avoid mixing the old repo-level Nextcloud config mounts with AIO

Minecraft:

- Cloudflare HTTP hostnames do not help for native Minecraft traffic
- verify `public-game` is enabled
- verify `PLAYIT_SECRET_KEY` is correct
- inspect `playit` logs if the public endpoint is not being assigned

### 6. Useful local-only endpoints

- Traefik router entrypoint: `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- Traefik dashboard: `http://127.0.0.1:${TRAEFIK_DASHBOARD_PORT:-8088}`
- Open WebUI direct local port: `http://127.0.0.1:3001`
- Nextcloud AIO setup interface: `https://127.0.0.1:8081`
- Ollama direct local port: `http://127.0.0.1:11434`

## Quick Tunnel With DuckDNS TXT

If you do not own a domain, you can use a temporary Cloudflare Quick Tunnel instead.
Treat this as a single-app access method, not the main ingress pattern for a full homelab:

```bash
bash scripts/quick_tunnel_duckdns.sh start http://127.0.0.1:3001
```

This script can also publish the live `trycloudflare.com` URL into a DuckDNS `TXT` record:

```bash
export DUCKDNS_DOMAIN=your-subdomain
export DUCKDNS_TOKEN=your-token
bash scripts/quick_tunnel_duckdns.sh start http://127.0.0.1:3001
```

By default, the script targets `QUICK_TUNNEL_LOCAL_URL`, which is set to `http://127.0.0.1:3001` in `.env.example`.
After the tunnel starts, open the root URL directly:

- `https://<random-subdomain>.trycloudflare.com`

Important:

- DuckDNS does not officially redirect your subdomain to the Quick Tunnel URL
- the script stores the live tunnel URL in `.quick-tunnel/current_url.txt`
- if DuckDNS credentials are set, it writes that same URL into the DuckDNS `TXT` record
- the Quick Tunnel URL changes when the tunnel is restarted
- Quick Tunnel is good for temporary Open WebUI access or testing a single service
- apps that require a stable hostname, multiple subdomains, or long-term public access are a poor fit for Quick Tunnel mode
- if Open WebUI was previously configured with a different external URL, update its `WebUI URL` setting to the current public hostname

Useful commands:

```bash
bash scripts/quick_tunnel_duckdns.sh status
bash scripts/quick_tunnel_duckdns.sh stop
bash scripts/quick_tunnel_duckdns.sh publish-txt
```

## Quick Tunnel Auto-Start

If you want the Quick Tunnel to survive reboots and keep DuckDNS TXT updated automatically:

```bash
cd ~/homelab
bash scripts/setup_quick_tunnel_service.sh
```

This installs `cloudflared` on the Pi host and creates a `systemd` service that:

- starts on boot
- waits for the local target from `QUICK_TUNNEL_LOCAL_URL`
- restarts the Quick Tunnel if it dies
- republishes the active `trycloudflare.com` URL to DuckDNS TXT every `QUICK_TUNNEL_SYNC_INTERVAL_SECONDS`

This host-level Quick Tunnel is separate from the Docker `cloudflared` container. Use one of these approaches:

- Quick Tunnel without a domain: point `QUICK_TUNNEL_LOCAL_URL` at one app, such as `http://127.0.0.1:3001`
- Owned-domain Cloudflare tunnel on the host: `COMPOSE_PROFILES=public-http`

If port `80` on the Pi is already taken by StellarMate or another service, that is fine. Traefik still defaults to host port `8089`, controlled by `TRAEFIK_HOST_PORT`, for local diagnostics only.

## One-Time GitHub Runner Setup (On Pi)

Create a runner token in:

- GitHub repo -> `Settings` -> `Actions` -> `Runners` -> `New self-hosted runner`

Then run:

```bash
cd ~/homelab
export RUNNER_TOKEN="paste_token_here"
export GH_OWNER="samarthpusalkar"
export GH_REPO="home_server"
bash scripts/setup_github_runner.sh
```

Runner labels include `homelab`, so workflow `.github/workflows/deploy-homelab.yml` can target it.

## First Deploy

```bash
cd ~/homelab
bash scripts/deploy.sh
```

After this, deploys happen automatically on push to `main`.

## Remote Restart

If you need to restart the stack without SSH:

1. Open GitHub Actions
2. Run `Restart Homelab`
3. Optionally enter a single compose service name such as `openwebui`

Normal pushes should already restart changed services automatically, so this is mainly for manual recovery.

## Admin Control

The stack now includes a protected admin panel for service operations:

- local URL: `http://127.0.0.1:8091`
- recommended public hostname: `https://admin.yourdomain.com`
- features: start, stop, enable auto-start, disable auto-start, and register future managed services

Generate the password hash on the Pi with:

```bash
cd ~/homelab
python scripts/hash_admin_password.py
```

Then copy that value into `ADMIN_PASSWORD_HASH` in `~/homelab/.env`.

Because the generated hash contains `$`, wrap it in single quotes inside `.env`, for example:

```bash
ADMIN_PASSWORD_HASH='pbkdf2_sha256$600000$...$...'
```

Secure cookies are enabled by default for the public admin hostname. If you specifically want to log into `http://127.0.0.1:8091` over plain HTTP from a browser on the Pi, set:

```bash
ADMIN_SECURE_COOKIES=0
```

If you want GitHub Actions or a trusted webhook to register or control services through the panel later, also set:

```bash
ADMIN_API_TOKEN=replace_with_a_long_random_secret
```

That token can authenticate bearer requests to:

- `GET /api/services`
- `POST /api/services/register`
- `POST /api/services/<service-key>/action/<start|stop|enable|disable>`

## Add A New Service (Any Type: EXIF, Image Gen, OCR, etc.)

1. Create service folder:
   - `services/<service-name>/Dockerfile`
   - app code and dependency files
2. Add service to `docker-compose.yml` with Traefik hostname labels.
3. Add admin-discovery labels so the control panel can pick it up automatically:
   - `homelab.admin.managed=true`
   - `homelab.admin.name=My Service`
   - `homelab.admin.exposure=traefik`
   - `homelab.admin.description=Short summary`
4. Add a public hostname in `~/homelab/.env` if you want it exposed through Cloudflare.
5. Commit and push to `main`.

### Service Compose Example

```yaml
imggen:
  build: ./services/imggen
  container_name: imggen
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.imggen.rule=Host(`${IMGGEN_PUBLIC_HOST:-imggen.example.com}`)"
    - "traefik.http.routers.imggen.entrypoints=web"
    - "traefik.http.services.imggen.loadbalancer.server.port=8000"
    - "homelab.admin.managed=true"
    - "homelab.admin.name=Image Gen"
    - "homelab.admin.exposure=traefik"
    - "homelab.admin.description=Example AI image generation service"
```

If you also want local direct testing, add:

```yaml
ports:
  - "8090:8000"
```

If a future service is created dynamically by GitHub Actions or another automation instead of being statically defined in `docker-compose.yml`, register it in the admin registry on the Pi with:

```bash
cd ~/homelab
python scripts/register_managed_service.py \
  --state-dir ./data/admin-control \
  --key cardmanagementsystem \
  --display-name "Card Management System" \
  --container-name cardmanagementsystem \
  --exposure traefik \
  --public-host cards.yourdomain.com
```

That keeps the admin panel and deploy reconciliation aware of the service even before you build richer dynamic compose generation on top of it.

## Recommended Starting Point

If you do not own a domain yet:

1. Use `COMPOSE_PROFILES=public-game,public-http`
2. Set `PLAYIT_SECRET_KEY`
3. Use the Quick Tunnel service only for temporary access to one app
4. Keep in mind the public URL is still a random `trycloudflare.com` address

If you later buy a domain:

1. Change to `COMPOSE_PROFILES=public-game,public-http`
2. Create one Cloudflare Tunnel public hostname per app, all pointing at `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
3. Keep Minecraft on its Playit static domain
4. Start exposing selected web apps by hostname
