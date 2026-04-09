#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="${REPO_DIR:-${DEFAULT_REPO_DIR}}"
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
    echo "[repair-nextcloud] Docker needs elevated access right now; trying sudo."
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

echo "[repair-nextcloud] Ensuring container is up"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env up -d nextcloud

echo "[repair-nextcloud] Repairing ownership and config permissions inside container"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env exec -T -u 0 nextcloud sh <<'EOF'
set -eu

backup_file() {
  file="$1"
  suffix="$2"
  ts="$(date +%Y%m%d%H%M%S)"
  dest="${file}.${suffix}.${ts}.bak"
  mv "$file" "$dest"
  echo "[repair-nextcloud] Moved $(basename "$file") aside to $(basename "$dest")."
}

validate_config_array() {
  file="$1"
  php -d display_errors=1 -r '
$file = $argv[1];
$CONFIG = [];
require $file;
if (!isset($CONFIG) || !is_array($CONFIG)) {
    fwrite(STDERR, basename($file) . " did not initialize \$CONFIG as an array.\n");
    exit(1);
}
' "$file"
}

lint_php_file() {
  file="$1"
  php -l "$file"
}

mkdir -p /var/www/html/config /var/www/html/data /var/www/html/custom_apps /var/www/html/themes
find /var/www/html/config -mindepth 1 ! -name 'reverse-proxy.config.php' -exec chown www-data:www-data {} +
chown -R www-data:www-data /var/www/html/data /var/www/html/custom_apps /var/www/html/themes
chown www-data:www-data /var/www/html/config
chmod 750 /var/www/html/config

if [ -f /var/www/html/config/config.php ]; then
  if [ ! -s /var/www/html/config/config.php ]; then
    backup_file /var/www/html/config/config.php empty
    echo "[repair-nextcloud] Found empty config.php and moved it aside for regeneration."
  elif ! lint_php_file /var/www/html/config/config.php >/tmp/nextcloud-config-lint.log 2>&1; then
    echo "[repair-nextcloud] config.php has a PHP syntax error."
    cat /tmp/nextcloud-config-lint.log
    backup_file /var/www/html/config/config.php syntax-error
    echo "[repair-nextcloud] Invalid config.php was moved aside for regeneration."
  elif ! validate_config_array /var/www/html/config/config.php >/tmp/nextcloud-config-validate.log 2>&1; then
    echo "[repair-nextcloud] config.php is readable PHP, but it does not initialize \$CONFIG correctly."
    cat /tmp/nextcloud-config-validate.log
    backup_file /var/www/html/config/config.php invalid-config
    echo "[repair-nextcloud] Invalid config.php was moved aside for regeneration."
  fi
fi

set -- /var/www/html/config/*.config.php
if [ -e "$1" ]; then
  for extra_config in "$@"; do
    if ! lint_php_file "$extra_config" >/tmp/nextcloud-extra-config-lint.log 2>&1; then
      echo "[repair-nextcloud] $(basename "$extra_config") has a PHP syntax error."
      cat /tmp/nextcloud-extra-config-lint.log
      if [ "$(basename "$extra_config")" = "reverse-proxy.config.php" ]; then
        echo "[repair-nextcloud] The managed reverse proxy config is broken; fix the mounted repo file and rerun."
        exit 11
      fi
      backup_file "$extra_config" syntax-error
      continue
    fi

    if ! validate_config_array "$extra_config" >/tmp/nextcloud-extra-config-validate.log 2>&1; then
      echo "[repair-nextcloud] $(basename "$extra_config") corrupts \$CONFIG when loaded."
      cat /tmp/nextcloud-extra-config-validate.log
      if [ "$(basename "$extra_config")" = "reverse-proxy.config.php" ]; then
        echo "[repair-nextcloud] The managed reverse proxy config is broken; fix the mounted repo file and rerun."
        exit 12
      fi
      backup_file "$extra_config" invalid-config
    fi
  done
fi
EOF

echo "[repair-nextcloud] Restarting nextcloud"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env restart nextcloud

echo "[repair-nextcloud] Recent nextcloud logs"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" "${PROFILE_ARGS[@]}" --env-file .env logs --tail=50 nextcloud
