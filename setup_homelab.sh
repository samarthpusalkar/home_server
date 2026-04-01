#!/bin/bash
set -e

echo "=== RPi Homelab Setup for StellarMate ==="
echo "Installing Docker, Docker Compose, and gocryptfs..."
sudo apt update
sudo apt install -y docker.io docker-compose gocryptfs

echo "Setting up Docker permissions..."
if ! groups $USER | grep -q '\bdocker\b'; then
  sudo usermod -aG docker $USER
  echo "Added $USER to docker group. You may need to log out and back in, or run 'newgrp docker'."
fi

echo "Creating directory structure under /opt/homelab..."
sudo mkdir -p /opt/homelab/data/{minecraft,ollama,openwebui,nextcloud,playit}
sudo mkdir -p /opt/homelab/secrets
sudo mkdir -p /opt/homelab/encrypted

echo "Fixing permissions for /opt/homelab..."
sudo chown -R $USER:$USER /opt/homelab

echo "Copying files to /opt/homelab..."
cp docker-compose.yml /opt/homelab/
cp astro_session.sh /opt/homelab/
cp encryption_setup.sh /opt/homelab/
cp .env.example /opt/homelab/
if [ ! -f /opt/homelab/.env ]; then
  cp /opt/homelab/.env.example /opt/homelab/.env
fi
chmod +x /opt/homelab/*.sh

echo "Done! Make sure you fill in /opt/homelab/.env and run ./encryption_setup.sh BEFORE starting docker-compose."
