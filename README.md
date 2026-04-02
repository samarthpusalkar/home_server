# Home Server Auto-Deploy Setup

This repo is set up so you only do SSH/manual setup once on a fresh Raspberry Pi, then future deploys happen on every push to `main`.

Your GitHub repo name (`home_server`) and local folder name (`homelab` or `~/homelab`) do not need to match.

## Profiles

Optional public-facing pieces are disabled unless you turn them on in `~/homelab/.env`:

- empty `COMPOSE_PROFILES` = local-only stack
- `COMPOSE_PROFILES=local-ollama` = run Ollama inside Docker on the Pi
- `COMPOSE_PROFILES=public-game` = enable Playit for games like Minecraft
- `COMPOSE_PROFILES=public-http` = enable Traefik for path-based local HTTP routing
- `COMPOSE_PROFILES=managed-cloudflare` = enable the Docker `cloudflared` container for owned-domain tunnels
- `COMPOSE_PROFILES=public-game,public-http` = games + Traefik router
- `COMPOSE_PROFILES=local-ollama,public-game,public-http,managed-cloudflare` = full public stack with Docker Ollama and owned-domain Cloudflare tunnel

## Public HTTP Model

HTTP apps now use one public entrypoint with path-based routing:

- `https://home.example.com/nextcloud`
- `https://home.example.com/openwebui`
- `https://home.example.com/custom_service1`

Cloudflare Tunnel should expose one local service:

- `http://traefik:80`

Traefik then routes each path to the right container.
The router now matches on path prefixes, so it works both with an owned domain and with a random Quick Tunnel hostname.

When you use a Quick Tunnel instead of an owned-domain Cloudflare tunnel, `cloudflared` runs on the Pi host as a `systemd` service and points at:

- `http://127.0.0.1:8089` by default

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
- `PUBLIC_APP_HOST`
- `PUBLIC_BASE_URL`
- `OPENWEBUI_PUBLIC_PATH`
- `NEXTCLOUD_PUBLIC_PATH`

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

This section is optional. Skip it unless you own a domain and want public HTTP apps such as Nextcloud or Open WebUI.

In Cloudflare Zero Trust -> Tunnels -> your tunnel -> Public Hostname:

- Hostname: `home.yourdomain.com`
- Service: `http://traefik:80`

After this is added, every new HTTP service can be exposed by adding a path rule in Traefik.

## Quick Tunnel With DuckDNS TXT

If you do not own a domain, you can use a temporary Cloudflare Quick Tunnel instead:

```bash
bash scripts/quick_tunnel_duckdns.sh start
```

This script can also publish the live `trycloudflare.com` URL into a DuckDNS `TXT` record:

```bash
export DUCKDNS_DOMAIN=your-subdomain
export DUCKDNS_TOKEN=your-token
bash scripts/quick_tunnel_duckdns.sh start
```

By default, the script targets `http://127.0.0.1:${TRAEFIK_HOST_PORT:-8089}`, which should be Traefik's local HTTP entrypoint for this stack.
After the tunnel starts, open Open WebUI at:

- `https://<random-subdomain>.trycloudflare.com${OPENWEBUI_PUBLIC_PATH:-/openwebui}`

Important:

- DuckDNS does not officially redirect your subdomain to the Quick Tunnel URL
- the script stores the live tunnel URL in `.quick-tunnel/current_url.txt`
- if DuckDNS credentials are set, it writes that same URL into the DuckDNS `TXT` record
- the Quick Tunnel URL changes when the tunnel is restarted
- simple path-based apps like Open WebUI can work through the random Quick Tunnel hostname
- apps that require a stable hostname, like Nextcloud, are a poor fit for Quick Tunnel mode
- if Open WebUI was previously configured with a different external URL, update its `WebUI URL` setting to the current public hostname and path

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

- Quick Tunnel without a domain: `COMPOSE_PROFILES=public-http`
- Owned-domain Cloudflare tunnel: `COMPOSE_PROFILES=public-http,managed-cloudflare`

If port `80` on the Pi is already taken by StellarMate or another service, that is fine. Traefik now defaults to host port `8089`, controlled by `TRAEFIK_HOST_PORT`, and the Quick Tunnel defaults to `http://127.0.0.1:8089`.

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
2. Add service to `docker-compose.yml` with Traefik path labels.
3. Add a public path in `~/homelab/.env` if you want it exposed through Cloudflare.
4. Commit and push to `main`.

### Service Compose Example

```yaml
imggen:
  build: ./services/imggen
  container_name: imggen
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.imggen.rule=PathPrefix(`${IMGGEN_PUBLIC_PATH:-/imggen}`)"
    - "traefik.http.routers.imggen.entrypoints=web"
    - "traefik.http.routers.imggen.middlewares=imggen-strip"
    - "traefik.http.middlewares.imggen-strip.stripprefix.prefixes=${IMGGEN_PUBLIC_PATH:-/imggen}"
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
3. Use the Quick Tunnel service if you want temporary remote web access
4. Keep in mind the public URL is still a random `trycloudflare.com` address

If you later buy a domain:

1. Change to `COMPOSE_PROFILES=public-game,public-http,managed-cloudflare`
2. Set `CLOUDFLARED_TOKEN`
3. Point Cloudflare Tunnel at `http://traefik:80`
4. Start exposing selected web apps by path
