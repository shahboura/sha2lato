#!/bin/sh
# sha2lato host update — run by CI over SSH (or by hand on the Docker host).
#
# Pulls the repo, pulls the registry image, recreates the stack, prunes.
#
# Local-build mode (someone builds the image on the host instead of using a
# registry): the pull step fails harmlessly, and `up` reuses the existing
# local image. After Dockerfile changes, rebuild manually with:
#   docker compose -f compose/docker-compose.yml up -d --build
set -eu

REPO_DIR="${SHA2LATO_DIR:-/opt/sha2lato}"
COMPOSE_FILE="compose/docker-compose.yml"

cd "$REPO_DIR"

log() { printf '[update] %s\n' "$*"; }

log "pulling $REPO_DIR"
git pull --ff-only

log "pulling images (registry mode; ignored if the image is built locally)"
docker compose -f "$COMPOSE_FILE" pull --ignore-pull-failures

log "recreating the stack"
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

log "pruning dangling images"
docker image prune -f >/dev/null 2>&1 || true

log "status"
docker compose -f "$COMPOSE_FILE" ps

log "done"
