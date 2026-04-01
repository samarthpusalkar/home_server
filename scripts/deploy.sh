#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/homelab}"
BRANCH="${BRANCH:-main}"
COMPOSE_FILES="${COMPOSE_FILES:-docker-compose.yml}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH."
  exit 1
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "Repository not found at $REPO_DIR."
  echo "Run scripts/bootstrap_fresh_pi.sh first."
  exit 1
fi

cd "$REPO_DIR"

echo "[deploy] Syncing branch $BRANCH in $REPO_DIR"
git fetch origin "$BRANCH"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  git checkout "$BRANCH"
fi

git pull --ff-only origin "$BRANCH"

declare -a COMPOSE_ARGS
IFS=':' read -r -a COMPOSE_FILE_ARRAY <<< "$COMPOSE_FILES"
for compose_file in "${COMPOSE_FILE_ARRAY[@]}"; do
  COMPOSE_ARGS+=(-f "$compose_file")
done

echo "[deploy] Pulling available images"
docker compose "${COMPOSE_ARGS[@]}" --env-file .env pull --ignore-pull-failures

echo "[deploy] Applying stack changes"
docker compose "${COMPOSE_ARGS[@]}" --env-file .env up -d --build --remove-orphans

echo "[deploy] Current status"
docker compose "${COMPOSE_ARGS[@]}" --env-file .env ps

