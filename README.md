# Home Server Auto-Deploy Setup

This repo is set up so you only do SSH/manual setup once on a fresh Raspberry Pi, then future deploys happen on every push to `main`.

Your GitHub repo name (`home_server`) and local folder name (`homelab` or `/opt/homelab`) do not need to match.

## Profiles

Optional public-facing pieces are disabled unless you turn them on in `/opt/homelab/.env`:

- empty `COMPOSE_PROFILES` = local-only stack
- `COMPOSE_PROFILES=public-game` = enable Playit for games like Minecraft
- `COMPOSE_PROFILES=public-http` = enable Traefik + Cloudflare Tunnel for web apps
- `COMPOSE_PROFILES=public-game,public-http` = enable both

## Public HTTP Model

HTTP apps now use one public hostname with path-based routing:

- `https://home.example.com/nextcloud`
- `https://home.example.com/openwebui`
- `https://home.example.com/custom_service1`

Cloudflare Tunnel should expose one local service:

- `http://traefik:80`

Traefik then routes each path to the right container.

## What Auto-Updates

On push to `main`, GitHub Actions (self-hosted runner on the Pi) will:

1. Pull latest git changes into `/opt/homelab`
2. Pull available container images
3. Rebuild local custom services in `services/*`
4. Run `docker compose up -d --build --remove-orphans` for the profiles enabled in `.env`

This means:

- new services are created automatically on push
- changed services are rebuilt and restarted automatically on push
- unchanged services normally stay up

## What Does Not Auto-Update

- `/opt/homelab/.env` values and secrets (you manage these manually)
- Cloudflare Zero Trust dashboard settings (only if you use `public-http`)
- DNS records outside your wildcard setup

## One-Time Setup (Fresh Pi)

Run once on the Raspberry Pi:

```bash
git clone https://github.com/samarthpusalkar/home_server.git /opt/homelab
cd /opt/homelab
bash scripts/bootstrap_fresh_pi.sh
```

Then edit:

```bash
nano /opt/homelab/.env
```

Set these base values:

- `WEBUI_SECRET_KEY`
- `NEXTCLOUD_ADMIN_USER`
- `NEXTCLOUD_ADMIN_PASSWORD`

Set these only if you enable `public-http`:

- `CLOUDFLARED_TOKEN`
- `PUBLIC_APP_SCHEME`
- `PUBLIC_APP_HOST`
- `PUBLIC_BASE_URL`
- `OPENWEBUI_PUBLIC_PATH`
- `NEXTCLOUD_PUBLIC_PATH`

If you only want Minecraft/public game access for now, you can leave Cloudflare values alone and set:

```bash
COMPOSE_PROFILES=public-game
```

## One-Time Cloudflare Tunnel Setup

This section is optional. Skip it unless you own a domain and want public HTTP apps such as Nextcloud or Open WebUI.

In Cloudflare Zero Trust -> Tunnels -> your tunnel -> Public Hostname:

- Hostname: `home.yourdomain.com`
- Service: `http://traefik:80`

After this is added, every new HTTP service can be exposed by adding a path rule in Traefik.

## One-Time GitHub Runner Setup (On Pi)

Create a runner token in:

- GitHub repo -> `Settings` -> `Actions` -> `Runners` -> `New self-hosted runner`

Then run:

```bash
cd /opt/homelab
export RUNNER_TOKEN="paste_token_here"
export GH_OWNER="samarthpusalkar"
export GH_REPO="home_server"
bash scripts/setup_github_runner.sh
```

Runner labels include `homelab`, so workflow `.github/workflows/deploy-homelab.yml` can target it.

## First Deploy

```bash
cd /opt/homelab
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
3. Add a public path in `/opt/homelab/.env` if you want it exposed through Cloudflare.
4. Commit and push to `main`.

### Service Compose Example

```yaml
imggen:
  build: ./services/imggen
  container_name: imggen
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.imggen.rule=Host(`${PUBLIC_APP_HOST}`) && PathPrefix(`${IMGGEN_PUBLIC_PATH:-/imggen}`)"
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

1. Use `COMPOSE_PROFILES=public-game`
2. Set only `PLAYIT_SECRET_KEY`
3. Ignore Cloudflare and Traefik for now
4. Keep Nextcloud and other web apps local on your LAN

If you later buy a domain:

1. Change to `COMPOSE_PROFILES=public-game,public-http`
2. Set `CLOUDFLARED_TOKEN`
3. Point Cloudflare Tunnel at `http://traefik:80`
4. Start exposing selected web apps by path
