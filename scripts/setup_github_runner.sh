#!/usr/bin/env bash
set -euo pipefail

GH_OWNER="${GH_OWNER:-samarthpusalkar}"
GH_REPO="${GH_REPO:-home_server}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-homelab}"
RUNNER_LABELS="${RUNNER_LABELS:-homelab,linux,arm64}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"

if [[ -z "$RUNNER_TOKEN" ]]; then
  echo "Set RUNNER_TOKEN first."
  echo "Get it from: GitHub repo -> Settings -> Actions -> Runners -> New self-hosted runner."
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64)
    RUNNER_ARCH="arm64"
    ;;
  x86_64|amd64)
    RUNNER_ARCH="x64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

RUNNER_VERSION="${RUNNER_VERSION:-$(
  curl -fsSL https://api.github.com/repos/actions/runner/releases/latest |
    sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p' |
    head -n1
)}"

if [[ -z "$RUNNER_VERSION" ]]; then
  echo "Failed to resolve runner version."
  exit 1
fi

RUNNER_TAR="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TAR}"

sudo mkdir -p "$RUNNER_DIR"
sudo chown -R "$USER:$USER" "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ ! -f ./config.sh ]]; then
  echo "Downloading GitHub runner ${RUNNER_VERSION} (${RUNNER_ARCH})"
  curl -fsSL -o "$RUNNER_TAR" "$RUNNER_URL"
  tar xzf "$RUNNER_TAR"
  rm -f "$RUNNER_TAR"
fi

if [[ ! -f ./.runner ]]; then
  ./config.sh \
    --url "https://github.com/${GH_OWNER}/${GH_REPO}" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --unattended \
    --replace
fi

sudo ./svc.sh install "$USER" || true
sudo ./svc.sh start
sudo ./svc.sh status || true

echo "Runner setup complete."
echo "Workflow label required: homelab"

