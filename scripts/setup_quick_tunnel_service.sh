#!/usr/bin/env bash
set -euo pipefail

HOMELAB_ROOT="${HOMELAB_ROOT:-${HOME}/homelab}"
SERVICE_NAME="${SERVICE_NAME:-homelab-quick-tunnel}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
RUN_AS_USER="${RUN_AS_USER:-$USER}"

detect_cloudflared_deb_arch() {
  local machine
  machine="$(uname -m)"

  case "$machine" in
    aarch64|arm64)
      printf '%s\n' "arm64"
      ;;
    armv7l|armhf)
      printf '%s\n' "armhf"
      ;;
    x86_64|amd64)
      printf '%s\n' "amd64"
      ;;
    *)
      echo "Unsupported architecture: $machine"
      exit 1
      ;;
  esac
}

install_cloudflared_if_missing() {
  if command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared is already installed."
    return 0
  fi

  local arch
  local temp_deb
  local download_url

  arch="$(detect_cloudflared_deb_arch)"
  temp_deb="/tmp/cloudflared-${arch}.deb"
  download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.deb"

  echo "Installing cloudflared for architecture: $arch"
  curl -fsSL -o "$temp_deb" "$download_url"
  sudo dpkg -i "$temp_deb"
  rm -f "$temp_deb"
}

write_systemd_service() {
  sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Homelab Cloudflare Quick Tunnel Supervisor
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=simple
User=${RUN_AS_USER}
WorkingDirectory=${HOMELAB_ROOT}
ExecStart=${HOMELAB_ROOT}/scripts/quick_tunnel_duckdns.sh watch
ExecStop=${HOMELAB_ROOT}/scripts/quick_tunnel_duckdns.sh stop
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

echo "=== Homelab Quick Tunnel Setup ==="
echo "Repo root: $HOMELAB_ROOT"
echo "Service: $SERVICE_NAME"
echo "Run as user: $RUN_AS_USER"

if [[ ! -f "${HOMELAB_ROOT}/scripts/quick_tunnel_duckdns.sh" ]]; then
  echo "Missing ${HOMELAB_ROOT}/scripts/quick_tunnel_duckdns.sh"
  echo "Run this script from the Pi after cloning or bootstrapping the repo."
  exit 1
fi

sudo apt update
sudo apt install -y curl ca-certificates

install_cloudflared_if_missing

sudo mkdir -p "${HOMELAB_ROOT}/.quick-tunnel"
sudo chown -R "${RUN_AS_USER}:${RUN_AS_USER}" "${HOMELAB_ROOT}/.quick-tunnel"

write_systemd_service

sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME"
sudo systemctl status "$SERVICE_NAME" --no-pager || true

echo "Quick Tunnel service installed."
echo "The host-level cloudflared process now starts on boot."
echo "Edit ${HOMELAB_ROOT}/.env to control QUICK_TUNNEL_* and DUCKDNS_* values."
echo "Set QUICK_TUNNEL_LOCAL_URL to the single local app you want to expose."
