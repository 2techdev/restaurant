#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# GastroCore Local Deploy Script
#
# Builds the Go server + Flutter web, then deploys to the VPS via LAN SSH.
# Run this from your local machine (same network as the VPS).
#
# Usage:
#   ./infra/deploy/deploy.sh [options]
#
# Options:
#   --no-web        Skip Flutter web build
#   --no-server     Skip Go server build
#   --no-deploy     Build artifacts only, do not push to server
#   --build-only    Same as --no-deploy
#   --skip-nginx    Do not update nginx config on remote
#   -h, --help      Show this help
#
# Environment overrides (with defaults):
#   SERVER_HOST   192.168.1.134
#   SERVER_USER   tech
#   SSH_KEY       ~/.ssh/id_ed25519
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─── Config (override via env) ────────────────────────────────────────────────
SERVER_HOST="${SERVER_HOST:-192.168.1.134}"
SERVER_USER="${SERVER_USER:-tech}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

REMOTE_HOME="/home/tech/gastrocore"
REMOTE_BIN_PATH="/usr/local/bin/gastrocore-server"
REMOTE_WEB="$REMOTE_HOME/web/dist"
COMPOSE_FILE="$REMOTE_HOME/docker-compose.prod.yml"

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

check_deps() {
  local missing=()
  for cmd in go flutter ssh scp; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"

  [[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"
  ok "Dependencies OK"
}

# ─── Build: Flutter Web ───────────────────────────────────────────────────────
build_web() {
  log "Building Flutter web (apps/online) ..."
  cd "$REPO_ROOT/apps/online"

  flutter pub get
  flutter build web --release

  # Custom domain CNAME
  echo "pos.2tech.ch" > build/web/CNAME

  # Bundle standalone demo page if it exists
  if [[ -f "web/demo/index.html" ]]; then
    mkdir -p build/web/demo
    cp web/demo/index.html build/web/demo/index.html
  fi

  ok "Flutter web build complete → apps/online/build/web/"
}

# ─── Build: Go Server ─────────────────────────────────────────────────────────
build_server() {
  log "Cross-compiling Go server (linux/amd64) ..."
  cd "$REPO_ROOT/server"

  mkdir -p bin
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
    go build -ldflags="-s -w" -o bin/gastrocore-server-linux ./cmd/server

  ok "Go binary built → server/bin/gastrocore-server-linux ($(du -sh bin/gastrocore-server-linux | cut -f1))"
}

# ─── Deploy ───────────────────────────────────────────────────────────────────
deploy_files() {
  local skip_nginx="${1:-false}"

  log "Connecting to $SERVER_USER@$SERVER_HOST ..."

  # Verify SSH connectivity
  ssh $SSH_OPTS "$SERVER_USER@$SERVER_HOST" true \
    || die "Cannot reach $SERVER_HOST — are you on the local network?"

  # ── Upload Go binary ────────────────────────────────────────────────────────
  log "Uploading Go binary ..."
  scp $SSH_OPTS \
    "$REPO_ROOT/server/bin/gastrocore-server-linux" \
    "$SERVER_USER@$SERVER_HOST:/tmp/gastrocore-server-new"

  # ── Upload Flutter web ──────────────────────────────────────────────────────
  log "Uploading Flutter web files ..."
  ssh $SSH_OPTS "$SERVER_USER@$SERVER_HOST" "mkdir -p $REMOTE_WEB"
  # rsync is faster if available; fall back to scp
  if ssh $SSH_OPTS "$SERVER_USER@$SERVER_HOST" command -v rsync &>/dev/null; then
    rsync -az --delete \
      -e "ssh $SSH_OPTS" \
      "$REPO_ROOT/apps/online/build/web/" \
      "$SERVER_USER@$SERVER_HOST:$REMOTE_WEB/"
  else
    ssh $SSH_OPTS "$SERVER_USER@$SERVER_HOST" "rm -rf $REMOTE_WEB/*"
    scp $SSH_OPTS -r \
      "$REPO_ROOT/apps/online/build/web/." \
      "$SERVER_USER@$SERVER_HOST:$REMOTE_WEB/"
  fi

  # ── Upload nginx config (unless skipped) ────────────────────────────────────
  if [[ "$skip_nginx" != true ]]; then
    log "Uploading nginx config ..."
    scp $SSH_OPTS \
      "$REPO_ROOT/infra/deploy/nginx-gastrocore.conf" \
      "$SERVER_USER@$SERVER_HOST:$REMOTE_HOME/nginx-gastrocore.conf"
  fi

  # ── Remote: swap binary & restart services ──────────────────────────────────
  log "Running remote deployment steps ..."

  # We pass variables by injecting them before the heredoc so the remote shell
  # does not need to know anything about our local environment.
  ssh $SSH_OPTS "$SERVER_USER@$SERVER_HOST" \
    REMOTE_HOME="$REMOTE_HOME" \
    REMOTE_BIN_PATH="$REMOTE_BIN_PATH" \
    COMPOSE_FILE="$COMPOSE_FILE" \
    SKIP_NGINX="$skip_nginx" \
    bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

log()  { printf '  \033[1;34m→\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m %s\n' "$*"; }

# ── Stop server ──────────────────────────────────────────────────────────────
if [[ -f "$COMPOSE_FILE" ]]; then
  log "Stopping Docker server container ..."
  if command -v docker &>/dev/null; then
    docker compose -f "$COMPOSE_FILE" stop server 2>/dev/null \
      || docker-compose -f "$COMPOSE_FILE" stop server 2>/dev/null \
      || warn "docker compose stop returned non-zero (container may not have been running)"
  fi
fi

if systemctl is-active --quiet gastrocore 2>/dev/null; then
  log "Stopping systemd gastrocore service ..."
  sudo systemctl stop gastrocore
fi

# ── Replace binary ───────────────────────────────────────────────────────────
log "Installing new binary at $REMOTE_BIN_PATH ..."
chmod +x /tmp/gastrocore-server-new
sudo mv /tmp/gastrocore-server-new "$REMOTE_BIN_PATH"
ok "Binary installed"

# ── Start server ─────────────────────────────────────────────────────────────
if [[ -f "$COMPOSE_FILE" ]]; then
  log "Starting Docker server container ..."
  if command -v docker &>/dev/null; then
    docker compose -f "$COMPOSE_FILE" up -d server 2>/dev/null \
      || docker-compose -f "$COMPOSE_FILE" up -d server 2>/dev/null \
      || warn "docker compose up returned non-zero"
  fi
fi

if systemctl list-unit-files --quiet 2>/dev/null | grep -q '^gastrocore\.service'; then
  log "Starting gastrocore systemd service ..."
  sudo systemctl start gastrocore
fi

# ── Nginx ────────────────────────────────────────────────────────────────────
if [[ "$SKIP_NGINX" != true && -f "$REMOTE_HOME/nginx-gastrocore.conf" ]]; then
  log "Updating nginx config ..."
  sudo cp "$REMOTE_HOME/nginx-gastrocore.conf" /etc/nginx/sites-available/gastrocore
  sudo ln -sf /etc/nginx/sites-available/gastrocore /etc/nginx/sites-enabled/gastrocore

  if sudo nginx -t 2>/dev/null; then
    sudo nginx -s reload
    ok "Nginx reloaded"
  else
    warn "Nginx config test failed — config not applied. Check manually."
  fi
fi

ok "Remote deployment complete"
REMOTE_SCRIPT

  ok "Deployed to $SERVER_HOST successfully!"
}

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  sed -n '/^# Usage/,/^# ─/p' "$0" | grep -v '^# ─' | sed 's/^# //'
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  local build_web=true
  local build_server=true
  local do_deploy=true
  local skip_nginx=false

  for arg in "$@"; do
    case "$arg" in
      --no-web)     build_web=false ;;
      --no-server)  build_server=false ;;
      --no-deploy|--build-only) do_deploy=false ;;
      --skip-nginx) skip_nginx=true ;;
      -h|--help)    usage; exit 0 ;;
      *) die "Unknown option: $arg (try --help)" ;;
    esac
  done

  log "GastroCore deploy — target: $SERVER_USER@$SERVER_HOST"
  echo

  check_deps

  [[ "$build_web"    == true ]] && build_web
  [[ "$build_server" == true ]] && build_server

  if [[ "$do_deploy" == true ]]; then
    deploy_files "$skip_nginx"
  else
    ok "Build-only mode — artifacts ready, not deployed"
    echo "  Go binary : $REPO_ROOT/server/bin/gastrocore-server-linux"
    echo "  Web files : $REPO_ROOT/apps/online/build/web/"
  fi
}

main "$@"
