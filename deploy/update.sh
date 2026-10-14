#!/bin/sh
# sha2lato host update — run by CI over SSH (or by hand on the Docker host).
#
# Detects the deployment mode from compose/.env and does the right thing:
#   build-on-host      (SHA2LATO_AGENT_IMAGE=sha2lato-agent:local) → rebuild + up
#   pull-from-registry (any other image ref)                       → pull + up
# See docs/configuration.md → "Deployment modes".
#
# Usage: ./deploy/update.sh [--dry-run]
set -eu

REPO_DIR="${SHA2LATO_DIR:-/opt/sha2lato}"
COMPOSE_FILE="compose/docker-compose.yml"

case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  "") DRY_RUN="" ;;
  *) echo "unknown option: $1 (only --dry-run)" >&2; exit 2 ;;
esac

cd "$REPO_DIR"

log() { printf '[update] %s\n' "$*"; }
run() {
  if [ -n "$DRY_RUN" ]; then
    printf '[update] dry-run:'
    printf ' %s' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# ── detect the deployment mode ──────────────────────────────────────────────
IMAGE=""
if [ -f compose/.env ]; then
  IMAGE=$(grep -E '^SHA2LATO_AGENT_IMAGE=' compose/.env 2>/dev/null | tail -n 1 | cut -d '=' -f 2- || true)
fi
if [ -z "$IMAGE" ]; then IMAGE="sha2lato-agent:local"; fi

case "$IMAGE" in
  *:local) MODE="build-on-host" ;;
  *) MODE="pull-from-registry" ;;
esac
log "image $IMAGE → mode $MODE"

log "pulling $REPO_DIR"
run git pull --ff-only

if [ "$MODE" = "build-on-host" ]; then
  log "rebuilding the image on the host"
  run docker compose -f "$COMPOSE_FILE" build
else
  log "pulling the registry image"
  run docker compose -f "$COMPOSE_FILE" pull
fi

log "recreating the stack"
run docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

log "pruning dangling images"
run docker image prune -f

log "status"
run docker compose -f "$COMPOSE_FILE" ps

log "done"
