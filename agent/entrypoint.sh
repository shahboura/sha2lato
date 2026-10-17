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

# ── Agent workflow pack (AGENT_PACK — one variable = pack + version) ───────
# AGENT_PACK=agents-opencode[@<ver>] (DEFAULT) → fetches the pack from npm
#   into the volume, then installs its agent/command/skill files into the
#   global OpenCode config. Bare or @latest → npm latest, re-resolved every
#   start (offline falls back to the cached copy).
# AGENT_PACK=superpowers[@<tag>] → merges the Superpowers plugin spec into
#   opencode.json. Bare or @latest → latest git tag (needs >= v6.4.1 on
#   OpenCode v2); offline keeps the current spec.
# AGENT_PACK=none → no workflow pack.
# Exact versions only (no ranges); one variable = exclusivity + version.
# superpowers manages git worktrees itself: keep KIMAKI_WORKTREES unset.
CONF_DIR="${XDG_CONFIG_HOME:-/data/opencode/config}/opencode"
CONF="$CONF_DIR/opencode.json"
PACK_MARKER="${XDG_CONFIG_HOME:-/data/opencode/config}/.agents-opencode-installed"
PACK_NPM_DIR="$(dirname "${XDG_CONFIG_HOME:-/data/opencode/config}")/npm"
AGENT_PACK_VAL="${AGENT_PACK:-agents-opencode}"

# Folded into AGENT_PACK=superpowers@<tag> — warn instead of silently ignoring.
if [ -n "${SUPERPOWERS_TAG:-}" ]; then
  echo "[entrypoint] WARNING: SUPERPOWERS_TAG is deprecated and ignored — use AGENT_PACK=superpowers@<tag>" >&2
fi

# Converge ~/.config/opencode onto the volume-backed XDG path — some tools
# (e.g. the agents-opencode installer) hardcode ~/.config/opencode.
mkdir -p /root/.config
if [ ! -L /root/.config/opencode ]; then
  rm -rf /root/.config/opencode
  ln -s "$CONF_DIR" /root/.config/opencode
fi

# Version of the agents-opencode copy currently on the volume, if any.
ao_installed_version() {
  AO_PKG_JSON="$PACK_NPM_DIR/node_modules/agents-opencode/package.json" \
    node -e 'console.log(require(process.env.AO_PKG_JSON).version)' 2>/dev/null || true
}

# Replace any "<prefix>*" plugin entry with <spec> (upsert). Returns nonzero
# when it could not write, so callers can skip their success line.
set_plugin_spec() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[entrypoint] WARNING: jq unavailable — add $1 to $CONF manually" >&2
    return 1
  fi
  mkdir -p "$CONF_DIR"
  [ -f "$CONF" ] || printf '{}\n' > "$CONF"
  TMP="$(mktemp "$CONF_DIR/.opencode.json.XXXXXX")"
  if jq --arg spec "$1" --arg prefix "$2" \
      '.plugins = (((.plugins // []) | map(select((type == "string" and startswith($prefix)) | not))) + [$spec])' \
      "$CONF" > "$TMP"; then
    mv "$TMP" "$CONF"
  else
    rm -f "$TMP"
    echo "[entrypoint] WARNING: could not update $CONF — add $1 manually" >&2
    return 1
  fi
}

# Drop every "<prefix>*" plugin entry (no-op when no config exists yet).
remove_plugin_specs() {
  [ -f "$CONF" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  TMP="$(mktemp "$CONF_DIR/.opencode.json.XXXXXX")"
  if jq --arg prefix "$1" \
      '.plugins = ((.plugins // []) | map(select((type == "string" and startswith($prefix)) | not)))' \
      "$CONF" > "$TMP"; then
    mv "$TMP" "$CONF"
  else
    rm -f "$TMP"
  fi
}

# A superpowers tag we're willing to put in the plugin spec: safe charset and
# a structurally valid git ref (rejects `..`, leading `-`, etc.). Applied to
# operator pins AND to tags resolved from the network.
sp_tag_ok() {
  case "$1" in
    ""|-*|*[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  git check-ref-format "refs/tags/$1" >/dev/null 2>&1
}

# Normalize cross-directory access to "ask" — OpenCode v2 evaluates permission
# rules in order (last match wins) and its canonical shape is the `permissions`
# array (`permission` is the deprecated v1 key). The fetched agents-opencode
# pack ships a blanket external_directory "deny": that would silently block
# this box's documented flows (new-project clones and `kimaki project add`
# write outside the session's project dir), while "ask" surfaces kimaki's
# Accept / Accept Always / Deny buttons in Discord. Runs on every start
# (idempotent): drop the legacy v1 external_directory entry (and the deprecated
# `permission` object itself, once nothing else is left in it), drop any
# external_directory rules from the v2 array, and append the canonical ask rule
# LAST. Other rules — v2 array entries and unrelated v1 keys — are left
# untouched. Per-agent permissions and "Accept Always" saved approvals remain
# the override levers.
normalize_external_directory() {
  [ -f "$CONF" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    echo "[entrypoint] WARNING: jq unavailable — add {\"action\":\"external_directory\",\"resource\":\"*\",\"effect\":\"ask\"} to the .permissions array in $CONF manually" >&2
    return 0
  fi
  TMP="$(mktemp "$CONF_DIR/.opencode.json.XXXXXX")" || { echo "[entrypoint] WARNING: cannot create a temp file in $CONF_DIR — will retry next start" >&2; return 0; }
  if jq 'if (.permission | type) == "object" then del(.permission.external_directory) else . end
        | if (.permission | type) == "object" then (if (.permission | length) == 0 then del(.permission) else . end) else . end
        | .permissions = (((.permissions // []) | map(select(if type == "object" then .action != "external_directory" else true end)))
                          + [{"action":"external_directory","resource":"*","effect":"ask"}])' \
      "$CONF" > "$TMP"; then
    if mv "$TMP" "$CONF"; then
      echo "[entrypoint] external_directory normalized to \"ask\" (v2 permissions array; cross-directory flows need it)"
    else
      rm -f "$TMP"
      echo "[entrypoint] WARNING: could not replace $CONF — will retry next start" >&2
    fi
  else
    rm -f "$TMP"
    echo "[entrypoint] WARNING: could not normalize $CONF — will retry next start" >&2
  fi
}

case "$AGENT_PACK_VAL" in
  agents-opencode|agents-opencode@*)
    # Resolve the wanted version: bare / @latest → npm latest; else exact x.y.z.
    AO_WANT="${AGENT_PACK_VAL#agents-opencode}"
    AO_WANT="${AO_WANT#@}"
    AO_SPEC="latest"
    AO_OK=1
    if [ "$AGENT_PACK_VAL" = "agents-opencode@" ]; then
      AO_OK=0
      echo "[entrypoint] WARNING: empty version after '@' in AGENT_PACK — expected agents-opencode or agents-opencode@<x.y.z>; pack skipped" >&2
    elif [ -n "$AO_WANT" ] && [ "$AO_WANT" != "latest" ]; then
      if printf '%s' "$AO_WANT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
        AO_SPEC="$AO_WANT"
      else
        AO_OK=0
        echo "[entrypoint] WARNING: invalid agents-opencode version '$AO_WANT' — expected exact x.y.z or 'latest'; pack skipped" >&2
      fi
    fi
    if [ "$AO_OK" -eq 1 ]; then
      AO_VER="$(ao_installed_version)"
      if [ "$AO_SPEC" != "latest" ] && [ "$AO_VER" = "$AO_SPEC" ]; then
        AO_SOURCE="cached"
      else
        mkdir -p "$PACK_NPM_DIR"
        if timeout 90 npm install --prefix "$PACK_NPM_DIR" --no-save --no-audit --no-fund --no-update-notifier --ignore-scripts --loglevel=error --cache "$PACK_NPM_DIR/.cache" "agents-opencode@$AO_SPEC" >/dev/null; then
          AO_VER="$(ao_installed_version)"
          AO_SOURCE="fetched ($AO_SPEC)"
        else
          AO_VER="$(ao_installed_version)"
          if [ -n "$AO_VER" ]; then
            AO_SOURCE="cached (fetch failed)"
            echo "[entrypoint] WARNING: npm fetch failed (offline?) — using cached agents-opencode $AO_VER" >&2
          else
            echo "[entrypoint] WARNING: npm fetch failed and no cached agents-opencode — pack skipped, will retry next start" >&2
          fi
        fi
      fi
      if [ -n "$AO_VER" ]; then
        # exec'd shells don't inherit entrypoint env — expose the CLI system-wide
        ln -sf "$PACK_NPM_DIR/node_modules/.bin/agents-opencode" /usr/local/bin/agents-opencode 2>/dev/null || true
        INSTALLED_VER="$(cat "$PACK_MARKER" 2>/dev/null || printf '')"
        if [ "$INSTALLED_VER" = "$AO_VER" ] && [ -d "$CONF_DIR/agents" ]; then
          echo "[entrypoint] agents-opencode pack already installed ($AO_VER, $AO_SOURCE)"
        elif "$PACK_NPM_DIR/node_modules/.bin/agents-opencode" --global; then
          printf '%s\n' "$AO_VER" > "$PACK_MARKER"
          echo "[entrypoint] agents-opencode pack installed (all languages, $AO_VER — $AO_SOURCE)"
        else
          echo "[entrypoint] WARNING: agents-opencode install failed — will retry next start" >&2
        fi
      fi
      # enforce pack exclusivity only once the agents pack is healthy — an
      # invalid value or a cold offline start must not strip a working superpowers
      if [ -n "$AO_VER" ] && [ -d "$CONF_DIR/agents" ]; then
        remove_plugin_specs "superpowers@"
      fi
    fi
    ;;
  superpowers|superpowers@*)
    export SUPERPOWERS_DISABLE_TELEMETRY="${SUPERPOWERS_DISABLE_TELEMETRY:-1}"
    SP_WANT="${AGENT_PACK_VAL#superpowers}"
    SP_WANT="${SP_WANT#@}"
    SP_REPO="https://github.com/obra/superpowers.git"
    SP_URL="git+${SP_REPO}"
    SP_TAG=""
    case "$AGENT_PACK_VAL" in
      superpowers@)
        echo "[entrypoint] WARNING: empty tag after '@' in AGENT_PACK — expected superpowers or superpowers@<tag>; pack skipped" >&2
        ;;
      superpowers|superpowers@latest)
        # Latest stable (non-prerelease) tag; offline keeps the current spec.
        SP_TAG="$(timeout 20 git ls-remote --tags --refs --sort=-v:refname "$SP_REPO" 'v*' 2>/dev/null | sed 's|.*refs/tags/||' | grep -v -- '-' | head -n1)"
        if [ -z "$SP_TAG" ] || ! sp_tag_ok "$SP_TAG"; then
          SP_TAG=""
          echo "[entrypoint] WARNING: could not resolve a valid latest superpowers tag (offline?) — keeping the current spec" >&2
        fi
        ;;
      *)
        if sp_tag_ok "$SP_WANT"; then
          SP_TAG="$SP_WANT"
        else
          echo "[entrypoint] WARNING: invalid superpowers tag '$SP_WANT' — expected a git tag or 'latest'; pack skipped" >&2
        fi
        ;;
    esac
    if [ -n "$SP_TAG" ]; then
      SP_SPEC="superpowers@${SP_URL}#${SP_TAG}"
      # Upsert replaces any previous superpowers spec so tag changes actually
      # converge (append-if-absent would leave two plugin entries).
      if set_plugin_spec "$SP_SPEC" "superpowers@"; then
        echo "[entrypoint] superpowers ${SP_TAG} enabled (merged into $CONF)"
      fi
    fi
    if [ -n "${KIMAKI_WORKTREES:-}" ]; then
      echo "[entrypoint] WARNING: KIMAKI_WORKTREES is set — superpowers manages git worktrees itself; leave Kimaki worktrees OFF" >&2
    fi
    ;;
  none)
    remove_plugin_specs "superpowers@"
    echo "[entrypoint] workflow pack disabled (AGENT_PACK=none)"
    ;;
  *)
    echo "[entrypoint] WARNING: unknown AGENT_PACK='${AGENT_PACK_VAL}' — expected agents-opencode[@x.y.z], superpowers[@tag], or none; ignoring" >&2
    ;;
esac

# ── Ponytail discipline plugin (PONYTAIL, default on) ──────────────────────
# Injects the minimal-code ruleset every turn plus /ponytail commands.
# Set PONYTAIL=0/off/false to strip it from the config.
PONYTAIL_SPEC="${PONYTAIL_SPEC:-@dietrichgebert/ponytail@5.2.0}"
case "${PONYTAIL:-1}" in
  0|off|false)
    remove_plugin_specs "@dietrichgebert/ponytail@"
    echo "[entrypoint] ponytail disabled (PONYTAIL=$PONYTAIL)"
    ;;
  *)
    if set_plugin_spec "$PONYTAIL_SPEC" "@dietrichgebert/ponytail@"; then
      echo "[entrypoint] ponytail plugin enabled ($PONYTAIL_SPEC)"
    fi
    ;;
esac

# Converge permissions after the pack and ponytail steps (either may create
# the config first) and before kimaki starts the OpenCode service (config is
# read at service start).
normalize_external_directory

# ── Git identity + optional SSH commit signing ─────────────────────────────
# A default identity is baked as system gitconfig ("sha2lato agent"); override
# with GIT_USER_NAME/GIT_USER_EMAIL. GIT_SIGN=1 enables SSH commit signing
# when /root/.ssh/signing_key exists — add signing_key.pub as a Signing Key
# on GitHub / your Forgejo account. See docs/usage.md → "Commits from the agent".
# Two-arg form (empirically verified: handles values with leading dashes;
# the `name=value` single-arg form is rejected by git config). Failures warn
# and continue rather than aborting the entrypoint.
if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --system user.name "$GIT_USER_NAME" || echo "[entrypoint] WARNING: could not set GIT_USER_NAME (ignored)" >&2
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --system user.email "$GIT_USER_EMAIL" || echo "[entrypoint] WARNING: could not set GIT_USER_EMAIL (ignored)" >&2
fi
case "${GIT_SIGN:-0}" in
  1|on|true)
    if [ -f /root/.ssh/signing_key ]; then
      git config --system gpg.format ssh
      git config --system user.signingkey /root/.ssh/signing_key
      git config --system commit.gpgsign true
      echo "[entrypoint] commit signing enabled (SSH, /root/.ssh/signing_key)"
    else
      echo "[entrypoint] WARNING: GIT_SIGN is set but /root/.ssh/signing_key not found — commits stay unsigned" >&2
    fi
    ;;
  *)
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
