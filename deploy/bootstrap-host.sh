#!/bin/sh
# sha2lato host bootstrap — first-time setup for a fresh Ubuntu/Debian host.
#
# Usage:
#   sudo ./bootstrap-host.sh [REPO_URL]
#
#   REPO_URL   git remote to clone into /opt/sha2lato, e.g.
#     git@forgejo.example.com:you/sha2lato.git   (SSH — needs a deploy key later)
#     https://github.com/you/sha2lato.git        (public repo — no key needed)
#
# Idempotent: safe to re-run. Sets up:
#   - Docker Engine + buildx + compose plugins (official apt repo)
#   - ufw firewall (SSH only)
#   - unattended-upgrades (OS-level CVE hygiene)
#   - /opt/sha2lato checkout + env files created from the *.example templates
#
# Docs: docs/hosting.md · docs/secrets.md · docs/discord-bot.md
set -eu

REPO_URL="${1:-}"
TARGET_DIR="${SHA2LATO_DIR:-/opt/sha2lato}"

log() { printf '\n[bootstrap] %s\n' "$*"; }
die() { printf '[bootstrap] error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] || die "this script targets Linux"
[ "$(id -u)" = "0" ] || die "run as root (sudo $0 ...)"
command -v apt-get >/dev/null 2>&1 || die "apt-get not found — this script targets Ubuntu/Debian"

# shellcheck source=/dev/null
. /etc/os-release
case "$ID" in
  ubuntu|debian) DOCKER_REPO="$ID" ;;
  *) die "unsupported distro: $ID (Ubuntu/Debian only)" ;;
esac

export DEBIAN_FRONTEND=noninteractive

log "installing base packages"
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::=--force-confold
apt-get install -y --no-install-recommends \
  ca-certificates curl git ufw unattended-upgrades

log "installing Docker (official apt repo)"
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
  curl -fsSL "https://download.docker.com/linux/${DOCKER_REPO}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_REPO} ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

log "configuring firewall (SSH only)"
ufw allow OpenSSH
# Keep any additional sshd ports open (enabling ufw must never lock you out).
# Read from sshd's own config — sudo strips SSH_* env vars (env_reset), so
# session variables cannot be trusted here. `sudo SSH_PORT=2222 ...` also works.
if [ -n "${SSH_PORT:-}" ]; then
  log "allowing SSH port ${SSH_PORT}/tcp (SSH_PORT)"
  ufw allow "${SSH_PORT}/tcp"
fi
if command -v sshd >/dev/null 2>&1; then
  (sshd -T 2>/dev/null || true) | awk '$1 == "port" { print $2 }' | while read -r p; do
    if [ -n "$p" ] && [ "$p" != "22" ]; then
      log "allowing sshd port ${p}/tcp"
      ufw allow "${p}/tcp"
    fi
  done
fi
ufw --force enable

log "enabling unattended-upgrades"
echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  log "adding $SUDO_USER to the docker group"
  usermod -aG docker "$SUDO_USER"
fi

if [ -n "$REPO_URL" ]; then
  if [ -d "$TARGET_DIR/.git" ]; then
    log "updating existing checkout at $TARGET_DIR"
    git -C "$TARGET_DIR" pull --ff-only
  else
    log "cloning $REPO_URL -> $TARGET_DIR"
    mkdir -p "$(dirname "$TARGET_DIR")"
    git clone "$REPO_URL" "$TARGET_DIR"
  fi
else
  log "no REPO_URL given — clone manually, then re-run with the path filled:"
  printf '    git clone <your-fork-url> %s\n' "$TARGET_DIR"
fi

if [ -d "$TARGET_DIR" ]; then
  mkdir -p "$TARGET_DIR/secrets/ssh"
  chmod 700 "$TARGET_DIR/secrets/ssh"
  [ -f "$TARGET_DIR/secrets/.env.agent" ] || cp "$TARGET_DIR/secrets/.env.agent.example" "$TARGET_DIR/secrets/.env.agent"
  [ -f "$TARGET_DIR/compose/.env" ] || cp "$TARGET_DIR/compose/.env.example" "$TARGET_DIR/compose/.env"
fi

# Hand the checkout to the invoking user: a non-root SSH deploy user must be
# able to run `git pull` (git refuses repos owned by another user) and edit
# secrets/.env.agent without sudo.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && [ -d "$TARGET_DIR" ]; then
  log "handing ownership of $TARGET_DIR to $SUDO_USER"
  chown -R "$SUDO_USER:$SUDO_USER" "$TARGET_DIR"
fi

cat <<EOF

[bootstrap] done. Next steps:

  1. Configure (asks for your Discord bot token, optional workflow pack):
       cd $TARGET_DIR && ./deploy/configure.sh
  2. Git SSH keys         add to $TARGET_DIR/secrets/ssh/       (docs/secrets.md)
  3. Registry image       edit $TARGET_DIR/compose/.env         (docs/ci-cd.md)
  4. Start the stack (build-on-host mode):
       cd $TARGET_DIR && docker compose -f compose/docker-compose.yml up -d --build
     Later updates:  cd $TARGET_DIR && ./deploy/update.sh   (detects the mode)
  5. Authorize the bot in your server:
       cd $TARGET_DIR && docker compose -f compose/docker-compose.yml exec agent kimaki bot install-url

EOF
