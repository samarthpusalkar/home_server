# Home Server Auto-Deploy Setup

This repo is set up so you only do SSH/manual setup once on a fresh Raspberry Pi, then future deploys happen on every push to `main`.

Your GitHub repo name (`home_server`) and local folder name (`homelab` or `/opt/homelab`) do not need to match.

## Profiles

Optional public-facing pieces are disabled unless you turn them on in `/opt/homelab/.env`:

- empty `COMPOSE_PROFILES` = local-only stack
- `COMPOSE_PROFILES=public-game` = enable Playit for games like Minecraft
- `COMPOSE_PROFILES=public-http` = enable Traefik + Cloudflare Tunnel for web apps
- `COMPOSE_PROFILES=public-game,public-http` = enable both

## What Auto-Updates

On push to `main`, GitHub Actions (self-hosted runner on the Pi) will:

1. Pull latest git changes into `/opt/homelab`
2. Pull available container images
3. Rebuild local custom services in `services/*`
4. Run `docker compose up -d --build --remove-orphans` for the profiles enabled in `.env`

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
- `OPENWEBUI_HOST`
- `NEXTCLOUD_HOST`

If you only want Minecraft/public game access for now, you can leave Cloudflare values alone and set:

```bash
COMPOSE_PROFILES=public-game
```

## One-Time Cloudflare Tunnel Setup

This section is optional. Skip it unless you own a domain and want public HTTP apps such as Nextcloud or Open WebUI.

In Cloudflare Zero Trust -> Tunnels -> your tunnel -> Public Hostname:

- Hostname: `*.yourdomain.com`
- Service: `http://traefik:80`

After this wildcard is added, every new HTTP service can be exposed just by adding Traefik labels and a host value in `.env`.

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

## Add A New Service (Any Type: EXIF, Image Gen, OCR, etc.)

1. Create service folder:
   - `services/<service-name>/Dockerfile`
   - app code and dependency files
2. Add service to `docker-compose.yml` with Traefik labels.
3. Add `<SERVICE>_HOST` in `/opt/homelab/.env` (for example `IMGGEN_HOST=imggen.yourdomain.com`).
4. Commit and push to `main`.

### Service Compose Example

```yaml
imggen:
  build: ./services/imggen
  container_name: imggen
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.imggen.rule=Host(`${IMGGEN_HOST:-imggen.example.com}`)"
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

1. Use `COMPOSE_PROFILES=public-game`
2. Set only `PLAYIT_SECRET_KEY`
3. Ignore Cloudflare and Traefik for now
4. Keep Nextcloud and other web apps local on your LAN

If you later buy a domain:

1. Change to `COMPOSE_PROFILES=public-game,public-http`
2. Set `CLOUDFLARED_TOKEN`
3. Configure the wildcard hostname in Cloudflare
4. Start exposing selected web apps by subdomain
