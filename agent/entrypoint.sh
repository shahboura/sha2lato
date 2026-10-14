#!/bin/sh
# sha2lato agent entrypoint.
#
#   no args : start the kimaki bot (headless self-hosted via KIMAKI_BOT_TOKEN,
#             which kimaki persists to /data/kimaki.db on first start)
#   args    : exec them — `docker compose run -it agent bash`,
#             `docker compose run -it agent kimaki --restart-onboarding`, ...

set -e

# ── Sync baked skills into the global OpenCode skills dir ──────────────────
# ui-ux-pro-max: always on. graphify usage guide: gated by GRAPHIFY
# (default 1; set 0/off/false to disable — removes it from the volume too).
# Copy-only for enabled skills; user-added skills are never touched.
SKILLS_DST="${XDG_CONFIG_HOME:-/data/opencode/config}/opencode/skills"
mkdir -p "$SKILLS_DST"

sync_skills() {
  if [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
    cp -r "$1"/. "$SKILLS_DST"/
    echo "[entrypoint] synced $2 skills -> $SKILLS_DST"
  fi
}

sync_skills /opt/skills "ui-ux-pro-max"
case "${GRAPHIFY:-1}" in
  0|off|false)
    rm -rf "$SKILLS_DST/graphify-usage"
    echo "[entrypoint] graphify guide disabled (GRAPHIFY=$GRAPHIFY)"
    ;;
  *)
    sync_skills /opt/skills-graphify "graphify guide"
    ;;
esac

# ── Agent workflow pack (AGENT_PACK — mutually exclusive, one workflow) ────
# AGENT_PACK=agents-opencode (DEFAULT) → installs the baked-in
#   agents-opencode pack (all languages) into the global OpenCode config.
# AGENT_PACK=superpowers → merges the Superpowers plugin line into
#   opencode.json (SUPERPOWERS_TAG, default v7.0.0; needs >= v6.4.1 on v2).
# AGENT_PACK=none → no workflow pack.
# One variable = exclusivity by construction.
# superpowers manages git worktrees itself: keep KIMAKI_WORKTREES unset.
CONF_DIR="${XDG_CONFIG_HOME:-/data/opencode/config}/opencode"
CONF="$CONF_DIR/opencode.json"
PACK_MARKER="${XDG_CONFIG_HOME:-/data/opencode/config}/.agents-opencode-installed"

# Converge ~/.config/opencode onto the volume-backed XDG path — some tools
# (e.g. the agents-opencode installer) hardcode ~/.config/opencode.
mkdir -p /root/.config
if [ ! -L /root/.config/opencode ]; then
  rm -rf /root/.config/opencode
  ln -s "$CONF_DIR" /root/.config/opencode
fi

case "${AGENT_PACK:-agents-opencode}" in
  agents-opencode)
    # enforce pack exclusivity at config level: drop superpowers plugin entries
    if [ -f "$CONF" ] && command -v jq >/dev/null 2>&1; then
      TMP="$(mktemp)"
      if jq '.plugins = ((.plugins // []) | map(select((type == "string" and startswith("superpowers@")) | not)))' "$CONF" > "$TMP"; then
        mv "$TMP" "$CONF"
      else
        rm -f "$TMP"
      fi
    fi
    if ! command -v agents-opencode >/dev/null 2>&1; then
      echo "[entrypoint] WARNING: AGENT_PACK=agents-opencode but the CLI is missing from the image" >&2
    else
      PACK_VER=$(node -p "require('$(npm root -g)/agents-opencode/package.json').version" 2>/dev/null || printf unknown)
      INSTALLED_VER=$(cat "$PACK_MARKER" 2>/dev/null || printf '')
      if [ "$INSTALLED_VER" = "$PACK_VER" ] && [ -d "$CONF_DIR/agents" ]; then
        echo "[entrypoint] agents-opencode pack already installed ($PACK_VER)"
      elif agents-opencode --global; then
        printf '%s\n' "$PACK_VER" > "$PACK_MARKER"
        echo "[entrypoint] agents-opencode pack installed (all languages, $PACK_VER)"
        # The pack defaults permission.external_directory to "deny", which
        # blocks this box's documented flows (new-project clones and
        # `kimaki project add` write outside the session's project dir).
        # Restore OpenCode's default ("ask") — in Discord, asks surface as
        # approve buttons in the thread. doom_loop stays "deny" (a feature).
        if command -v jq >/dev/null 2>&1 && [ -f "$CONF" ]; then
          TMP="$(mktemp)"
          if jq '.permission.external_directory = "ask"' "$CONF" > "$TMP"; then
            mv "$TMP" "$CONF"
            echo "[entrypoint] permission.external_directory set to \"ask\" (cross-directory flows need it)"
          else
            rm -f "$TMP"
          fi
        fi
      else
        echo "[entrypoint] WARNING: agents-opencode install failed — will retry next start" >&2
      fi
    fi
    ;;
  superpowers)
    export SUPERPOWERS_DISABLE_TELEMETRY="${SUPERPOWERS_DISABLE_TELEMETRY:-1}"
    SUPER_TAG="${SUPERPOWERS_TAG:-v7.0.0}"
    SUPER_SPEC="superpowers@git+https://github.com/obra/superpowers.git#${SUPER_TAG}"
    mkdir -p "$CONF_DIR"
    if [ ! -f "$CONF" ]; then
      printf '{\n  "plugins": ["%s"]\n}\n' "$SUPER_SPEC" > "$CONF"
      echo "[entrypoint] superpowers ${SUPER_TAG} enabled (created $CONF)"
    elif command -v jq >/dev/null 2>&1; then
      TMP="$(mktemp)"
      if jq --arg spec "$SUPER_SPEC" '.plugins = ((.plugins // []) | if index($spec) then . else . + [$spec] end)' "$CONF" > "$TMP"; then
        mv "$TMP" "$CONF"
        echo "[entrypoint] superpowers ${SUPER_TAG} enabled (merged into $CONF)"
      else
        rm -f "$TMP"
        echo "[entrypoint] WARNING: could not update $CONF — add the plugin line manually" >&2
      fi
    else
      echo "[entrypoint] WARNING: $CONF exists — add the superpowers plugin line manually" >&2
    fi
    if [ -n "${KIMAKI_WORKTREES:-}" ]; then
      echo "[entrypoint] WARNING: KIMAKI_WORKTREES is set — superpowers manages git worktrees itself; leave Kimaki worktrees OFF" >&2
    fi
    ;;
  none)
    echo "[entrypoint] workflow pack disabled (AGENT_PACK=none)"
    ;;
  *)
    echo "[entrypoint] WARNING: unknown AGENT_PACK='${AGENT_PACK}' — expected agents-opencode, superpowers, or none; ignoring" >&2
    ;;
esac

# ── Ponytail discipline plugin (PONYTAIL, default on) ──────────────────────
# Injects the minimal-code ruleset every turn plus /ponytail commands.
# Set PONYTAIL=0/off/false to strip it from the config.
PONYTAIL_SPEC="${PONYTAIL_SPEC:-@dietrichgebert/ponytail@5.2.0}"
case "${PONYTAIL:-1}" in
  0|off|false)
    if [ -f "$CONF" ] && command -v jq >/dev/null 2>&1; then
      TMP="$(mktemp)"
      if jq '.plugins = ((.plugins // []) | map(select((type == "string" and startswith("@dietrichgebert/ponytail@")) | not)))' "$CONF" > "$TMP"; then
        mv "$TMP" "$CONF"
      else
        rm -f "$TMP"
      fi
    fi
    echo "[entrypoint] ponytail disabled (PONYTAIL=$PONYTAIL)"
    ;;
  *)
    mkdir -p "$CONF_DIR"
    if [ ! -f "$CONF" ]; then
      printf '{\n  "plugins": ["%s"]\n}\n' "$PONYTAIL_SPEC" > "$CONF"
      echo "[entrypoint] ponytail plugin enabled (created $CONF)"
    elif command -v jq >/dev/null 2>&1; then
      TMP="$(mktemp)"
      if jq --arg spec "$PONYTAIL_SPEC" '.plugins = ((.plugins // []) | if index($spec) then . else . + [$spec] end)' "$CONF" > "$TMP"; then
        mv "$TMP" "$CONF"
        echo "[entrypoint] ponytail plugin enabled (merged into $CONF)"
      else
        rm -f "$TMP"
        echo "[entrypoint] WARNING: could not update $CONF for ponytail" >&2
      fi
    else
      echo "[entrypoint] WARNING: jq unavailable — add $PONYTAIL_SPEC to $CONF manually" >&2
    fi
    ;;
esac

# ── Passthrough mode ───────────────────────────────────────────────────────
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

# ── Wait for the DinD sidecar (best effort, 30s) ───────────────────────────
# The bot does not need docker; only project builds do. Warn and continue.
if [ -n "$DOCKER_HOST" ]; then
  i=0
  until docker info >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
      echo "[entrypoint] WARNING: docker daemon at $DOCKER_HOST unreachable after 30s; starting without it" >&2
      break
    fi
    sleep 1
  done
fi

# ── Start the bot ──────────────────────────────────────────────────────────
MACHINE_NAME="${MACHINE_NAME:-sha2lato}"
DATA_DIR="${KIMAKI_DATA_DIR:-/data}"

set -- kimaki --data-dir "$DATA_DIR" --machine-name "$MACHINE_NAME"
if [ -n "$KIMAKI_WORKTREES" ]; then
  set -- "$@" --worktrees
fi

echo "[entrypoint] starting kimaki (machine: $MACHINE_NAME, data: $DATA_DIR)"
exec "$@"
