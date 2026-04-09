#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-${HOME}/homelab}"
BRANCH="${BRANCH:-main}"
COMPOSE_FILES="${COMPOSE_FILES:-docker-compose.yml}"
PROFILE_STRING="${COMPOSE_PROFILES:-}"

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
    echo "[deploy] Docker needs elevated access right now; trying sudo."
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

read_env_value() {
  local key="$1"
  local value=""

  if [[ -f .env ]]; then
    value="$(grep -E "^${key}=" .env | tail -n 1 || true)"
    value="${value#${key}=}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
  fi

  printf '%s\n' "$value"
}

resolve_python_cmd() {
  if command -v python >/dev/null 2>&1; then
    PYTHON_CMD=(python)
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD=(python3)
    return 0
  fi

  echo "Neither 'python' nor 'python3' is available."
  exit 1
}

REPO_DIR="$(expand_path "$REPO_DIR")"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH."
  exit 1
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "Repository not found at $REPO_DIR."
  echo "Run scripts/bootstrap_fresh_pi.sh first."
  exit 1
fi

declare -a DOCKER_PREFIX=()
declare -a COMPOSE_CMD=()
declare -a PYTHON_CMD=()
resolve_docker_prefix
resolve_compose_cmd
resolve_python_cmd

cd "$REPO_DIR"

echo "[deploy] Syncing branch $BRANCH in $REPO_DIR"
git fetch origin "$BRANCH"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  git checkout "$BRANCH"
fi

git pull --ff-only origin "$BRANCH"

declare -a COMPOSE_ARGS=()
declare -a PROFILE_ARGS=()
IFS=':' read -r -a COMPOSE_FILE_ARRAY <<< "$COMPOSE_FILES"
for compose_file in "${COMPOSE_FILE_ARRAY[@]}"; do
  COMPOSE_ARGS+=(-f "$compose_file")
done

if [[ -z "$PROFILE_STRING" && -f .env ]]; then
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

if [[ "${#PROFILE_ARGS[@]}" -gt 0 ]]; then
  echo "[deploy] Enabling profiles: $PROFILE_STRING"
else
  echo "[deploy] No optional profiles enabled"
fi

echo "[deploy] Pulling available images"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env pull --ignore-pull-failures

echo "[deploy] Applying stack changes"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env up -d --build --remove-orphans

DATA_ROOT_VALUE="${DATA_ROOT:-}"
if [[ -z "$DATA_ROOT_VALUE" ]]; then
  DATA_ROOT_VALUE="$(read_env_value DATA_ROOT)"
fi
DATA_ROOT_VALUE="${DATA_ROOT_VALUE:-./data}"
STATE_DIR="$(expand_path "$DATA_ROOT_VALUE")/admin-control"

echo "[deploy] Reconciling admin-controlled auto-start state"
if [[ "${#DOCKER_PREFIX[@]}" -gt 0 ]]; then
  "${PYTHON_CMD[@]}" scripts/reconcile_managed_services.py --state-dir "$STATE_DIR" --docker-prefix "${DOCKER_PREFIX[0]}"
else
  "${PYTHON_CMD[@]}" scripts/reconcile_managed_services.py --state-dir "$STATE_DIR"
fi

echo "[deploy] Current status"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env ps
