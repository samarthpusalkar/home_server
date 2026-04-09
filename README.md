# Home Server Auto-Deploy Setup

This repo is set up so you only do SSH/manual setup once on a fresh Raspberry Pi, then future deploys happen on every push to `main`.

Your GitHub repo name (`home_server`) and local folder name (`homelab` or `~/homelab`) do not need to match.

## Profiles

Optional public-facing pieces are disabled unless you turn them on in `~/homelab/.env`:

- empty `COMPOSE_PROFILES` = local-only stack
- `COMPOSE_PROFILES=local-ollama` = run Ollama inside Docker on the Pi
- `COMPOSE_PROFILES=public-game` = enable Playit for games like Minecraft
- `COMPOSE_PROFILES=public-http` = enable Traefik for host-based local HTTP routing
- `COMPOSE_PROFILES=managed-cloudflare` = enable the Docker `cloudflared` container for owned-domain tunnels
- `COMPOSE_PROFILES=public-game,public-http` = games + Traefik router
- `COMPOSE_PROFILES=local-ollama,public-game,public-http,managed-cloudflare` = full public stack with Docker Ollama and owned-domain Cloudflare tunnel

## Public HTTP Model

HTTP apps should use dedicated hostnames at the site root:

- `https://drive.example.com`
- `https://chat.example.com`
- `https://imggen.example.com`

This is more scalable than path prefixes because apps like Open WebUI, Nextcloud,
and many admin dashboards expect to live at `/` on their own hostname.

Cloudflare Tunnel still exposes one local service:

- `http://traefik:80`

Traefik then routes each hostname to the right container.
One Cloudflare Tunnel can publish many hostnames, all pointing at the same local Traefik service.
You do not need one separate tunnel per subdomain.

Recommended ingress strategy for this repo:

- web apps such as Open WebUI and Nextcloud: Cloudflare Tunnel + Traefik + one subdomain per app
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
- `nextcloud`: file sync and web app; recommended public hostname `drive.example.com`
- `traefik`: local HTTP router for subdomain-based routing; usually keep private and use it behind Cloudflare Tunnel
- `cloudflared`: managed Cloudflare Tunnel client for owned domains
- `playit`: public TCP/UDP agent for games like Minecraft

Recommended subdomain map with `example.com` placeholders:

- `chat.example.com` -> Open WebUI
- `drive.example.com` -> Nextcloud
- `api.example.com` -> optional future Ollama API exposure if you really want it public
- no subdomain needed for `minecraft`; expose through Playit instead
- no subdomain needed for `traefik`; keep local on `127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- no subdomain needed for `cloudflared` or `playit`; they are transport services, not user-facing apps

Recommended starting point for your homelab:

- `chat.example.com` -> Open WebUI
- `drive.example.com` -> Nextcloud
- keep Ollama private at first
- keep Traefik dashboard private at first
- use Playit for Minecraft

## Cloudflare Setup Map

Use one Cloudflare Tunnel, not one tunnel per subdomain.

Inside Cloudflare Zero Trust -> Tunnels -> your tunnel -> Public Hostname, create:

- `chat.yourdomain.com` -> `http://traefik:80`
- `drive.yourdomain.com` -> `http://traefik:80`
- `api.yourdomain.com` -> `http://traefik:80` only if you later add a public API service

Do not create Cloudflare HTTP tunnel hostnames for:

- `minecraft.yourdomain.com` if you mean actual Minecraft gameplay
- Traefik dashboard unless you intentionally secure and expose it later
- Ollama unless you explicitly want the raw API reachable from the internet

For your current intended setup, the Cloudflare public hostnames to add are:

- `chat.example.com` -> `http://traefik:80`
- `drive.example.com` -> `http://traefik:80`

If you want to keep it minimal for first boot, create only:

- `chat.example.com` -> `http://traefik:80`

and add Nextcloud after Open WebUI is stable.

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

## What Does Not Auto-Update

- `~/homelab/.env` values and secrets (you manage these manually)
- Cloudflare Zero Trust dashboard settings (only if you use `public-http`)
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
- `NEXTCLOUD_ADMIN_USER`
- `NEXTCLOUD_ADMIN_PASSWORD`
- `OLLAMA_BASE_URL`

Set these only if you enable `public-http`:

- `PUBLIC_APP_SCHEME`
- `OPENWEBUI_PUBLIC_HOST`
- `OPENWEBUI_PUBLIC_URL`
- `OPENWEBUI_CORS_ALLOW_ORIGIN`
- `NEXTCLOUD_PUBLIC_HOST`
- `NEXTCLOUD_PUBLIC_URL`

The committed `.env.example` uses `example.com` placeholders only. Put your real domain only in your local `.env`.

Set these only if you enable `managed-cloudflare`:

- `CLOUDFLARED_TOKEN`

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

In Cloudflare Zero Trust -> Tunnels -> your tunnel -> Public Hostname, create one hostname per app and point each one to:

- Service: `http://traefik:80`

Examples:

- `chat.yourdomain.com` -> `http://traefik:80`
- `drive.yourdomain.com` -> `http://traefik:80`
- `imggen.yourdomain.com` -> `http://traefik:80`

After this is added, every new HTTP service can be exposed by adding a hostname rule in Traefik.

Example mapping if your domain is `example.com`:

- `chat.example.com` -> `http://traefik:80` for Open WebUI
- `drive.example.com` -> `http://traefik:80` for Nextcloud
- `api.example.com` -> `http://traefik:80` only if you later choose to publish Ollama or another HTTP API

Then set matching values in `~/homelab/.env`, for example:

```bash
COMPOSE_PROFILES=local-ollama,public-game,public-http,managed-cloudflare

OPENWEBUI_PUBLIC_HOST=chat.example.com
OPENWEBUI_PUBLIC_URL=https://chat.example.com
OPENWEBUI_CORS_ALLOW_ORIGIN=https://chat.example.com;http://127.0.0.1:3001;http://localhost:3001

NEXTCLOUD_PUBLIC_HOST=drive.example.com
NEXTCLOUD_PUBLIC_URL=https://drive.example.com
NEXTCLOUD_TRUSTED_DOMAINS=localhost 127.0.0.1 drive.example.com
```

For Minecraft, keep using the `minecraft` container on port `25565` and expose it with the `public-game` Playit profile rather than Cloudflare HTTP routing.

## Bring-Up Checklist

1. Copy `.env.example` to `.env` on the Pi.
2. Set your secrets:
   - `WEBUI_SECRET_KEY`
   - `NEXTCLOUD_ADMIN_USER`
   - `NEXTCLOUD_ADMIN_PASSWORD`
   - `CLOUDFLARED_TOKEN` if using owned-domain Cloudflare Tunnel
   - `PLAYIT_SECRET_KEY` if using Minecraft public access
3. Set profiles based on what you want running:
   - `COMPOSE_PROFILES=local-ollama,public-http,managed-cloudflare` for Open WebUI + Nextcloud + Docker Ollama
   - add `public-game` if you also want Minecraft via Playit
4. Set app hostnames in `.env`:
   - `OPENWEBUI_PUBLIC_HOST=chat.yourdomain.com`
   - `OPENWEBUI_PUBLIC_URL=https://chat.yourdomain.com`
   - `OPENWEBUI_CORS_ALLOW_ORIGIN=https://chat.yourdomain.com;http://127.0.0.1:3001;http://localhost:3001`
   - `NEXTCLOUD_PUBLIC_HOST=drive.yourdomain.com`
   - `NEXTCLOUD_PUBLIC_URL=https://drive.yourdomain.com`
   - `NEXTCLOUD_TRUSTED_DOMAINS=localhost 127.0.0.1 drive.yourdomain.com`
5. If using Docker Ollama, set:
   - `OLLAMA_BASE_URL=http://ollama:11434`
6. In Cloudflare Tunnel, add one Public Hostname per HTTP app and point each to `http://traefik:80`.
7. Run:

```bash
cd ~/homelab
bash scripts/deploy.sh
```

## Debugging Guide

Work from inside outward: container -> local port -> Traefik -> cloudflared -> public hostname.

### 1. Check container state

```bash
cd ~/homelab
docker compose --env-file .env ps
docker compose --env-file .env logs -f openwebui
docker compose --env-file .env logs -f nextcloud
docker compose --env-file .env logs -f cloudflared
docker compose --env-file .env logs -f playit
docker compose --env-file .env logs -f ollama
```

### 2. Check direct local app reachability on the Pi

```bash
curl -I http://127.0.0.1:3001
curl -I http://127.0.0.1:8081
curl -I http://127.0.0.1:11434
```

Expected meaning:

- `3001` responds = Open WebUI container is up
- `8081` responds = Nextcloud container is up
- `11434` responds = Ollama is reachable

### 3. Check Traefik routing before blaming Cloudflare

Run these on the Pi:

```bash
curl -I -H 'Host: chat.yourdomain.com' http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}
curl -I -H 'Host: drive.yourdomain.com' http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}
```

Expected meaning:

- success here but failure on the public hostname usually means Cloudflare Tunnel hostname config is wrong
- failure here means the problem is local Traefik labels, missing profiles, or missing env values

### 4. Check Cloudflare Tunnel itself

```bash
docker compose --env-file .env logs --tail=100 cloudflared
```

Things to verify:

- `managed-cloudflare` is included in `COMPOSE_PROFILES`
- `CLOUDFLARED_TOKEN` is set correctly
- each Cloudflare Public Hostname points to `http://traefik:80`
- the hostname in Cloudflare exactly matches the hostname in your `.env`

### 5. Check common app-specific issues

Open WebUI:

- wrong `OPENWEBUI_PUBLIC_URL` can cause odd redirects or login/session issues
- wrong `OPENWEBUI_CORS_ALLOW_ORIGIN` can cause browser-side API failures
- wrong `OLLAMA_BASE_URL` means the UI loads but models/chat fail

Nextcloud:

- missing public host in `NEXTCLOUD_TRUSTED_DOMAINS` causes trusted domain errors
- mismatched `NEXTCLOUD_PUBLIC_HOST` / `NEXTCLOUD_PUBLIC_URL` can break redirects
- proxy issues usually point to `NEXTCLOUD_TRUSTED_PROXIES` or tunnel/proxy headers

Minecraft:

- Cloudflare HTTP hostnames do not help for native Minecraft traffic
- verify `public-game` is enabled
- verify `PLAYIT_SECRET_KEY` is correct
- inspect `playit` logs if the public endpoint is not being assigned

### 6. Useful local-only endpoints

- Traefik router entrypoint: `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`
- Traefik dashboard: `http://127.0.0.1:${TRAEFIK_DASHBOARD_PORT:-8088}`
- Open WebUI direct local port: `http://127.0.0.1:3001`
- Nextcloud direct local port: `http://127.0.0.1:8081`
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
- Owned-domain Cloudflare tunnel: `COMPOSE_PROFILES=public-http,managed-cloudflare`

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

## Add A New Service (Any Type: EXIF, Image Gen, OCR, etc.)

1. Create service folder:
   - `services/<service-name>/Dockerfile`
   - app code and dependency files
2. Add service to `docker-compose.yml` with Traefik hostname labels.
3. Add a public hostname in `~/homelab/.env` if you want it exposed through Cloudflare.
4. Commit and push to `main`.

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
```

If you also want local direct testing, add:

```yaml
ports:
  - "8090:8000"
```

## Recommended Starting Point

If you do not own a domain yet:

1. Use `COMPOSE_PROFILES=public-game,public-http`
2. Set `PLAYIT_SECRET_KEY`
3. Use the Quick Tunnel service only for temporary access to one app
4. Keep in mind the public URL is still a random `trycloudflare.com` address

If you later buy a domain:

1. Change to `COMPOSE_PROFILES=public-game,public-http,managed-cloudflare`
2. Set `CLOUDFLARED_TOKEN`
3. Create one Cloudflare Tunnel public hostname per app, all pointing at `http://traefik:80`
4. Start exposing selected web apps by hostname
