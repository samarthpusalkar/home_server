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

resolve_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
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

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "Repository not found at $REPO_DIR."
  echo "Run scripts/bootstrap_fresh_pi.sh first."
  exit 1
fi

declare -a COMPOSE_CMD
resolve_compose_cmd

cd "$REPO_DIR"

echo "[deploy] Syncing branch $BRANCH in $REPO_DIR"
git fetch origin "$BRANCH"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  git checkout "$BRANCH"
fi

git pull --ff-only origin "$BRANCH"

declare -a COMPOSE_ARGS
declare -a PROFILE_ARGS
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

echo "[deploy] Current status"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env ps
