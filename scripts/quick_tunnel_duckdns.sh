#!/usr/bin/env bash
set -euo pipefail

COMMAND="${1:-start}"
COMMAND_ARG="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_ROOT="${HOMELAB_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ENV_FILE="${ENV_FILE:-$HOMELAB_ROOT/.env}"

STATE_DIR=""
PID_FILE=""
LOG_FILE=""
URL_FILE=""
LAST_PUBLISHED_URL_FILE=""
DUCKDNS_RESPONSE_FILE=""
LOCAL_URL=""
TUNNEL_TIMEOUT_SECONDS=""
TARGET_WAIT_SECONDS=""
CHECK_INTERVAL_SECONDS=""
SYNC_INTERVAL_SECONDS=""
RESTART_DELAY_SECONDS=""
CLOUDFLARED_BIN=""
DUCKDNS_DOMAIN=""
DUCKDNS_TOKEN=""
PUBLISH_DUCKDNS_TXT=""
CLEAR_DUCKDNS_TXT_ON_STOP=""

expand_path() {
  local path="$1"
  path="${path/#\~/$HOME}"
  path="${path//\$HOME/$HOME}"
  printf '%s\n' "$path"
}

read_env_value() {
  local key="$1"
  local default_value="${2:-}"
  local line=""
  local value=""

  if [[ -n "${!key-}" ]]; then
    printf '%s\n' "${!key}"
    return 0
  fi

  if [[ -f "$ENV_FILE" ]]; then
    line="$(grep -E "^${key}=" "$ENV_FILE" | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      value="${line#*=}"
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      printf '%s\n' "$value"
      return 0
    fi
  fi

  printf '%s\n' "$default_value"
}

refresh_config() {
  STATE_DIR="$(read_env_value QUICK_TUNNEL_STATE_DIR "$HOMELAB_ROOT/.quick-tunnel")"
  STATE_DIR="$(expand_path "$STATE_DIR")"
  PID_FILE="$STATE_DIR/cloudflared.pid"
  LOG_FILE="$STATE_DIR/cloudflared.log"
  URL_FILE="$STATE_DIR/current_url.txt"
  LAST_PUBLISHED_URL_FILE="$STATE_DIR/last_published_url.txt"
  DUCKDNS_RESPONSE_FILE="$STATE_DIR/duckdns-response.txt"
  LOCAL_URL="${COMMAND_ARG:-$(read_env_value QUICK_TUNNEL_LOCAL_URL "http://127.0.0.1:80")}"
  TUNNEL_TIMEOUT_SECONDS="$(read_env_value TUNNEL_TIMEOUT_SECONDS "60")"
  TARGET_WAIT_SECONDS="$(read_env_value QUICK_TUNNEL_TARGET_WAIT_SECONDS "300")"
  CHECK_INTERVAL_SECONDS="$(read_env_value QUICK_TUNNEL_CHECK_INTERVAL_SECONDS "10")"
  SYNC_INTERVAL_SECONDS="$(read_env_value QUICK_TUNNEL_SYNC_INTERVAL_SECONDS "600")"
  RESTART_DELAY_SECONDS="$(read_env_value QUICK_TUNNEL_RESTART_DELAY_SECONDS "10")"
  CLOUDFLARED_BIN="$(read_env_value CLOUDFLARED_BIN "cloudflared")"
  DUCKDNS_DOMAIN="$(read_env_value DUCKDNS_DOMAIN "")"
  DUCKDNS_TOKEN="$(read_env_value DUCKDNS_TOKEN "")"
  PUBLISH_DUCKDNS_TXT="$(read_env_value PUBLISH_DUCKDNS_TXT "1")"
  CLEAR_DUCKDNS_TXT_ON_STOP="$(read_env_value CLEAR_DUCKDNS_TXT_ON_STOP "0")"

  mkdir -p "$STATE_DIR"
}

usage() {
  cat <<EOF
Usage:
  scripts/quick_tunnel_duckdns.sh start [local_url]
  scripts/quick_tunnel_duckdns.sh stop
  scripts/quick_tunnel_duckdns.sh status
  scripts/quick_tunnel_duckdns.sh watch
  scripts/quick_tunnel_duckdns.sh reconcile
  scripts/quick_tunnel_duckdns.sh publish-txt [quick_tunnel_url]

Environment or .env values:
  QUICK_TUNNEL_LOCAL_URL=http://127.0.0.1:80
  QUICK_TUNNEL_STATE_DIR=~/homelab/.quick-tunnel
  QUICK_TUNNEL_TARGET_WAIT_SECONDS=300
  QUICK_TUNNEL_CHECK_INTERVAL_SECONDS=10
  QUICK_TUNNEL_SYNC_INTERVAL_SECONDS=600
  DUCKDNS_DOMAIN=your-subdomain
  DUCKDNS_TOKEN=your-duckdns-token

Notes:
  - Quick Tunnels are temporary and get a new trycloudflare URL after restart.
  - DuckDNS cannot officially redirect to that URL.
  - This script publishes the active Quick Tunnel URL into DuckDNS TXT instead.
EOF
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

normalize_duckdns_domain() {
  local domain="$1"
  domain="${domain%.duckdns.org}"
  printf '%s\n' "$domain"
}

pid_is_running() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

extract_tunnel_url() {
  if [[ ! -f "$LOG_FILE" ]]; then
    return 1
  fi

  grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$LOG_FILE" | tail -n 1
}

write_current_url() {
  local url="$1"
  if [[ -n "$url" ]]; then
    printf '%s\n' "$url" > "$URL_FILE"
  fi
}

current_url() {
  if [[ -f "$URL_FILE" ]]; then
    cat "$URL_FILE"
    return 0
  fi

  extract_tunnel_url || true
}

require_duckdns_credentials() {
  if [[ -z "$DUCKDNS_DOMAIN" || -z "$DUCKDNS_TOKEN" ]]; then
    echo "Set DUCKDNS_DOMAIN and DUCKDNS_TOKEN first."
    exit 1
  fi
}

duckdns_enabled() {
  [[ "$PUBLISH_DUCKDNS_TXT" != "0" && -n "$DUCKDNS_DOMAIN" && -n "$DUCKDNS_TOKEN" ]]
}

publish_duckdns_txt() {
  local url="$1"
  local domain
  domain="$(normalize_duckdns_domain "$DUCKDNS_DOMAIN")"

  require_duckdns_credentials
  require_command curl

  curl -fsS --get "https://www.duckdns.org/update" \
    --data-urlencode "domains=$domain" \
    --data-urlencode "token=$DUCKDNS_TOKEN" \
    --data-urlencode "txt=$url" \
    --data-urlencode "verbose=true" | tee "$DUCKDNS_RESPONSE_FILE"

  printf '%s\n' "$url" > "$LAST_PUBLISHED_URL_FILE"
}

clear_duckdns_txt() {
  local domain
  domain="$(normalize_duckdns_domain "$DUCKDNS_DOMAIN")"

  require_duckdns_credentials
  require_command curl

  curl -fsS --get "https://www.duckdns.org/update" \
    --data-urlencode "domains=$domain" \
    --data-urlencode "token=$DUCKDNS_TOKEN" \
    --data-urlencode "clear=true" | tee "$DUCKDNS_RESPONSE_FILE"

  rm -f "$LAST_PUBLISHED_URL_FILE"
}

publish_current_url_if_needed() {
  local force="${1:-0}"
  local url=""
  local last_published=""

  if ! duckdns_enabled; then
    return 0
  fi

  url="$(current_url || true)"
  if [[ -z "$url" ]]; then
    return 1
  fi

  if [[ -f "$LAST_PUBLISHED_URL_FILE" ]]; then
    last_published="$(cat "$LAST_PUBLISHED_URL_FILE")"
  fi

  if [[ "$force" != "1" && "$url" == "$last_published" ]]; then
    return 0
  fi

  log "Publishing Quick Tunnel URL to DuckDNS TXT: $url"
  publish_duckdns_txt "$url"
}

refresh_known_url_from_logs() {
  local discovered_url=""
  local stored_url=""

  discovered_url="$(extract_tunnel_url || true)"
  if [[ -z "$discovered_url" ]]; then
    return 1
  fi

  if [[ -f "$URL_FILE" ]]; then
    stored_url="$(cat "$URL_FILE")"
  fi

  if [[ "$discovered_url" != "$stored_url" ]]; then
    write_current_url "$discovered_url"
    if duckdns_enabled; then
      publish_current_url_if_needed 1
    fi
  fi

  return 0
}

wait_for_local_target() {
  require_command curl

  local waited=0
  while (( waited < TARGET_WAIT_SECONDS )); do
    if curl -sS --max-time 5 --output /dev/null "$LOCAL_URL"; then
      return 0
    fi

    sleep 2
    waited=$((waited + 2))
  done

  return 1
}

wait_for_tunnel_url() {
  local pid="$1"
  local waited=0
  local url=""

  while (( waited < TUNNEL_TIMEOUT_SECONDS )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi

    url="$(extract_tunnel_url || true)"
    if [[ -n "$url" ]]; then
      write_current_url "$url"
      return 0
    fi

    sleep 1
    waited=$((waited + 1))
  done

  return 1
}

start_cloudflared_process() {
  local detach="${1:-0}"

  require_command "$CLOUDFLARED_BIN"

  : > "$LOG_FILE"
  rm -f "$URL_FILE"

  if [[ "$detach" == "1" ]]; then
    nohup "$CLOUDFLARED_BIN" tunnel --url "$LOCAL_URL" >>"$LOG_FILE" 2>&1 &
  else
    "$CLOUDFLARED_BIN" tunnel --url "$LOCAL_URL" >>"$LOG_FILE" 2>&1 &
  fi

  local pid=$!
  echo "$pid" > "$PID_FILE"
  printf '%s\n' "$pid"
}

start_tunnel() {
  refresh_config

  if pid_is_running; then
    echo "Quick Tunnel already running."
    status_tunnel
    return 0
  fi

  if ! wait_for_local_target; then
    echo "Local target did not become reachable in time: $LOCAL_URL"
    exit 1
  fi

  local pid
  pid="$(start_cloudflared_process 1)"

  if ! wait_for_tunnel_url "$pid"; then
    echo "cloudflared exited before a Quick Tunnel URL was detected."
    tail -n 40 "$LOG_FILE" || true
    rm -f "$PID_FILE"
    exit 1
  fi

  publish_current_url_if_needed 1 || true
  status_tunnel
}

stop_tunnel() {
  refresh_config

  if pid_is_running; then
    local pid
    pid="$(cat "$PID_FILE")"
    kill "$pid" 2>/dev/null || true

    for _ in $(seq 1 10); do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done

    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi

    echo "Stopped Quick Tunnel process $pid."
  else
    echo "No running Quick Tunnel process found."
  fi

  rm -f "$PID_FILE"

  if [[ "$CLEAR_DUCKDNS_TXT_ON_STOP" == "1" && -n "$DUCKDNS_DOMAIN" && -n "$DUCKDNS_TOKEN" ]]; then
    echo "Clearing DuckDNS TXT record..."
    clear_duckdns_txt
  fi
}

status_tunnel() {
  refresh_config

  local url=""
  local last_published=""

  url="$(current_url || true)"
  if [[ -f "$LAST_PUBLISHED_URL_FILE" ]]; then
    last_published="$(cat "$LAST_PUBLISHED_URL_FILE")"
  fi

  if pid_is_running; then
    echo "Quick Tunnel is running."
    echo "PID: $(cat "$PID_FILE")"
  else
    echo "Quick Tunnel is not running."
  fi

  echo "Local target: $LOCAL_URL"
  if [[ -n "$url" ]]; then
    echo "Current URL: $url"
  fi
  if [[ -n "$last_published" ]]; then
    echo "Last published TXT URL: $last_published"
  fi
  echo "Log file: $LOG_FILE"
}

publish_txt_from_existing_url() {
  refresh_config

  local url="${COMMAND_ARG:-}"
  if [[ -z "$url" ]]; then
    url="$(current_url || true)"
  fi

  if [[ -z "$url" ]]; then
    echo "No Quick Tunnel URL available. Pass one explicitly or run start first."
    exit 1
  fi

  publish_duckdns_txt "$url"
}

reconcile_tunnel() {
  refresh_config

  if pid_is_running; then
    refresh_known_url_from_logs || true
    publish_current_url_if_needed 1 || true
    status_tunnel
    return 0
  fi

  log "Quick Tunnel is not running; starting it again."
  start_tunnel
}

watch_tunnel() {
  refresh_config
  require_command curl
  require_command "$CLOUDFLARED_BIN"

  local last_sync_epoch=0

  while true; do
    refresh_config

    if ! wait_for_local_target; then
      log "Local target is not reachable yet: $LOCAL_URL"
      sleep "$RESTART_DELAY_SECONDS"
      continue
    fi

    log "Starting Cloudflare Quick Tunnel for $LOCAL_URL"
    local pid
    pid="$(start_cloudflared_process 0)"

    if ! wait_for_tunnel_url "$pid"; then
      log "Quick Tunnel failed before a URL was assigned; retrying."
      rm -f "$PID_FILE"
      sleep "$RESTART_DELAY_SECONDS"
      continue
    fi

    refresh_known_url_from_logs || true
    publish_current_url_if_needed 1 || true
    last_sync_epoch="$(date +%s)"

    while kill -0 "$pid" 2>/dev/null; do
      refresh_config
      refresh_known_url_from_logs || true

      local now
      now="$(date +%s)"
      if (( now - last_sync_epoch >= SYNC_INTERVAL_SECONDS )); then
        publish_current_url_if_needed 1 || true
        last_sync_epoch="$now"
      fi

      sleep "$CHECK_INTERVAL_SECONDS"
    done

    log "Quick Tunnel process exited; restarting after ${RESTART_DELAY_SECONDS}s."
    rm -f "$PID_FILE"
    sleep "$RESTART_DELAY_SECONDS"
  done
}

case "$COMMAND" in
  start)
    start_tunnel
    ;;
  stop)
    stop_tunnel
    ;;
  status)
    status_tunnel
    ;;
  watch)
    watch_tunnel
    ;;
  reconcile)
    reconcile_tunnel
    ;;
  publish-txt)
    publish_txt_from_existing_url
    ;;
  *)
    usage
    exit 1
    ;;
esac
