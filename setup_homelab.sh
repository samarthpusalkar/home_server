#!/bin/bash
set -e

HOMELAB_ROOT="${HOMELAB_ROOT:-$HOME/homelab}"

echo "=== RPi Homelab Setup for StellarMate ==="
echo "Installing Docker, Docker Compose, and gocryptfs..."
sudo apt update
if ! sudo apt install -y docker.io docker-compose-plugin gocryptfs; then
  sudo apt install -y docker.io docker-compose gocryptfs
fi

echo "Setting up Docker permissions..."
if ! groups $USER | grep -q '\bdocker\b'; then
  sudo usermod -aG docker $USER
  echo "Added $USER to docker group. You may need to log out and back in, or run 'newgrp docker'."
fi

echo "Creating base directories under $HOMELAB_ROOT..."
sudo mkdir -p "$HOMELAB_ROOT/secrets"
sudo mkdir -p "$HOMELAB_ROOT/encrypted"
sudo chown -R $USER:$USER "$HOMELAB_ROOT"

echo "Copying files to $HOMELAB_ROOT..."
cp docker-compose.yml "$HOMELAB_ROOT/"
cp astro_session.sh "$HOMELAB_ROOT/"
cp encryption_setup.sh "$HOMELAB_ROOT/"
cp .env.example "$HOMELAB_ROOT/"
cp -R scripts "$HOMELAB_ROOT/"
cp -R config "$HOMELAB_ROOT/"
cp -R services "$HOMELAB_ROOT/"
cp README.md "$HOMELAB_ROOT/" 2>/dev/null || true
if [ ! -f "$HOMELAB_ROOT/.env" ]; then
  cp "$HOMELAB_ROOT/.env.example" "$HOMELAB_ROOT/.env"
fi

# Priority order:
# 1) exported DATA_ROOT in current shell
# 2) DATA_ROOT inside $HOMELAB_ROOT/.env
# 3) default ./data (relative to $HOMELAB_ROOT)
DATA_ROOT_FROM_ENVFILE=$(grep -E '^DATA_ROOT=' "$HOMELAB_ROOT/.env" | tail -n 1 || true)
DATA_ROOT_FROM_ENVFILE="${DATA_ROOT_FROM_ENVFILE#DATA_ROOT=}"
DATA_ROOT_FROM_ENVFILE="${DATA_ROOT_FROM_ENVFILE%\"}"
DATA_ROOT_FROM_ENVFILE="${DATA_ROOT_FROM_ENVFILE#\"}"
DATA_ROOT_FROM_ENVFILE="${DATA_ROOT_FROM_ENVFILE%\'}"
DATA_ROOT_FROM_ENVFILE="${DATA_ROOT_FROM_ENVFILE#\'}"

DATA_ROOT_VALUE="${DATA_ROOT:-$DATA_ROOT_FROM_ENVFILE}"
DATA_ROOT_VALUE="${DATA_ROOT_VALUE:-./data}"

if [[ "$DATA_ROOT_VALUE" = /* ]]; then
  DATA_ROOT_PATH="$DATA_ROOT_VALUE"
else
  DATA_ROOT_PATH="$HOMELAB_ROOT/$DATA_ROOT_VALUE"
fi

echo "Creating data directories under $DATA_ROOT_PATH..."
for service_dir in minecraft ollama openwebui nextcloud playit; do
  sudo mkdir -p "$DATA_ROOT_PATH/$service_dir"
done

echo "Fixing permissions..."
sudo chown -R $USER:$USER "$HOMELAB_ROOT"
sudo chown -R $USER:$USER "$DATA_ROOT_PATH"

chmod +x "$HOMELAB_ROOT"/*.sh
chmod +x "$HOMELAB_ROOT"/scripts/*.sh 2>/dev/null || true

echo "Done!"
echo "Next steps:"
echo "1) Fill in $HOMELAB_ROOT/.env and choose COMPOSE_PROFILES"
echo "2) If Docker says permission denied, run 'newgrp docker' once or log out/back in"
echo "3) Run $HOMELAB_ROOT/scripts/deploy.sh"
echo "4) If using Quick Tunnel, run $HOMELAB_ROOT/scripts/setup_quick_tunnel_service.sh"
echo "5) If using owned-domain Cloudflare Tunnel, point it at http://traefik:80"
echo "6) Configure GitHub runner with $HOMELAB_ROOT/scripts/setup_github_runner.sh"
