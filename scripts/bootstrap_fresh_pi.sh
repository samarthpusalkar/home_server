#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/samarthpusalkar/home_server.git}"
BRANCH="${BRANCH:-main}"
HOMELAB_ROOT="${HOMELAB_ROOT:-/opt/homelab}"

echo "=== Fresh Raspberry Pi bootstrap ==="
echo "Repo: $REPO_URL"
echo "Branch: $BRANCH"
echo "Target dir: $HOMELAB_ROOT"

sudo apt update
if ! sudo apt install -y git curl ca-certificates docker.io docker-compose-plugin; then
  sudo apt install -y git curl ca-certificates docker.io docker-compose
fi

NEEDS_RELOGIN=0
if ! groups "$USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  NEEDS_RELOGIN=1
fi

sudo mkdir -p "$HOMELAB_ROOT"
sudo chown -R "$USER:$USER" "$HOMELAB_ROOT"

if [[ -d "$HOMELAB_ROOT/.git" ]]; then
  git -C "$HOMELAB_ROOT" fetch origin "$BRANCH"
  git -C "$HOMELAB_ROOT" pull --ff-only origin "$BRANCH"
else
  if [[ -n "$(ls -A "$HOMELAB_ROOT" 2>/dev/null)" ]]; then
    echo "$HOMELAB_ROOT is not empty and not a git repo. Empty it manually, then rerun."
    exit 1
  fi
  git clone --branch "$BRANCH" "$REPO_URL" "$HOMELAB_ROOT"
fi

if [[ ! -f "$HOMELAB_ROOT/.env" ]]; then
  cp "$HOMELAB_ROOT/.env.example" "$HOMELAB_ROOT/.env"
fi

mkdir -p "$HOMELAB_ROOT/data"/{minecraft,ollama,openwebui,nextcloud,playit}

echo "Bootstrap complete."
echo "Next:"
echo "1) Edit $HOMELAB_ROOT/.env with real secrets and hostnames."
echo "2) Run scripts/deploy.sh once to start the stack."
echo "3) If using owned-domain Cloudflare Tunnel, set it to http://traefik:80."
echo "4) If using Quick Tunnel, run scripts/setup_quick_tunnel_service.sh."
echo "5) Install a GitHub self-hosted runner using scripts/setup_github_runner.sh."

if [[ "$NEEDS_RELOGIN" -eq 1 ]]; then
  echo "You were added to the docker group. Log out and back in (or run: newgrp docker)."
fi
