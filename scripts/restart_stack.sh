#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-${HOME}/homelab}"
COMPOSE_FILES="${COMPOSE_FILES:-docker-compose.yml}"
PROFILE_STRING="${COMPOSE_PROFILES:-}"
SERVICE_NAME="${SERVICE_NAME:-}"

expand_path() {
  local path="$1"
  path="${path/#\~/$HOME}"
  path="${path//\$HOME/$HOME}"
  printf '%s\n' "$path"
}

resolve_docker_prefix() {
  if docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=()
    return 0
  fi

  if sudo -n docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=(sudo)
    return 0
  fi

  if [[ -t 0 ]]; then
    echo "[restart] Docker needs elevated access right now; trying sudo."
    if sudo -v && sudo docker info >/dev/null 2>&1; then
      DOCKER_PREFIX=(sudo)
      return 0
    fi
  fi

  if id -nG "$USER" | grep -qw docker; then
    echo "Docker access is still denied for $USER even though the docker group is present."
    echo "Run 'newgrp docker' or log out and back in, then retry."
  else
    echo "Current user cannot access Docker."
    echo "Run 'sudo usermod -aG docker $USER' and then log out/back in."
  fi
  exit 1
}

resolve_compose_cmd() {
  if "${DOCKER_PREFIX[@]}" docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=("${DOCKER_PREFIX[@]}" docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=("${DOCKER_PREFIX[@]}" docker-compose)
    return 0
  fi

  echo "Neither 'docker compose' nor 'docker-compose' is available."
  exit 1
}

REPO_DIR="$(expand_path "$REPO_DIR")"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH."
  exit 1
fi

if [[ ! -f "$REPO_DIR/.env" ]]; then
  echo "Missing $REPO_DIR/.env"
  exit 1
fi

declare -a DOCKER_PREFIX=()
declare -a COMPOSE_CMD=()
resolve_docker_prefix
resolve_compose_cmd

cd "$REPO_DIR"

declare -a COMPOSE_ARGS=()
declare -a PROFILE_ARGS=()
IFS=':' read -r -a COMPOSE_FILE_ARRAY <<< "$COMPOSE_FILES"
for compose_file in "${COMPOSE_FILE_ARRAY[@]}"; do
  COMPOSE_ARGS+=(-f "$compose_file")
done

if [[ -z "$PROFILE_STRING" ]]; then
  PROFILE_STRING="$(grep -E '^COMPOSE_PROFILES=' .env | tail -n 1 || true)"
  PROFILE_STRING="${PROFILE_STRING#COMPOSE_PROFILES=}"
  PROFILE_STRING="${PROFILE_STRING%\"}"
  PROFILE_STRING="${PROFILE_STRING#\"}"
  PROFILE_STRING="${PROFILE_STRING%\'}"
  PROFILE_STRING="${PROFILE_STRING#\'}"
fi

PROFILE_STRING="${PROFILE_STRING// /}"
if [[ -n "$PROFILE_STRING" ]]; then
  IFS=',' read -r -a PROFILE_ARRAY <<< "$PROFILE_STRING"
  for profile in "${PROFILE_ARRAY[@]}"; do
    if [[ -n "$profile" ]]; then
      PROFILE_ARGS+=(--profile "$profile")
    fi
  done
fi

if [[ -n "$SERVICE_NAME" ]]; then
  echo "[restart] Restarting service: $SERVICE_NAME"
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env restart "$SERVICE_NAME"
else
  echo "[restart] Restarting enabled stack"
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env restart
fi
