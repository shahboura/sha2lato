#!/bin/sh
# sha2lato configure — one place to set the box's knobs.
#
# Interactive:      ./deploy/configure.sh
# Non-interactive:  ./deploy/configure.sh --token <t> [--machine <m>]
#                   [--pack agents-opencode|superpowers|none]
#                   [--worktrees on|off] [--ponytail on|off] [--graphify on|off]
#                   [--image local|<registry-ref>]
# Show current:     ./deploy/configure.sh --show
#
# Writes secrets/.env.agent (chmod 600) and compose/.env.
# Safe to re-run: current values are offered as defaults.
# Docs: docs/configuration.md
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
AGENT_ENV="$REPO_ROOT/secrets/.env.agent"
AGENT_EX="$REPO_ROOT/secrets/.env.agent.example"
COMPOSE_ENV="$REPO_ROOT/compose/.env"
COMPOSE_EX="$REPO_ROOT/compose/.env.example"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "error: $*" >&2; exit 1; }

get_val() {
  v=$(grep -E "^$1=" "$2" 2>/dev/null | tail -n 1 | cut -d '=' -f 2- | sed 's/[[:space:]]*#.*//' | tr -d '\r' || true)
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "${3:-}"; fi
}

set_val() {
  # set_val KEY VALUE FILE — replace the KEY= line (or append it)
  sb_tmp=$(mktemp)
  if ! awk -v k="$1" -v v="$2" '
    index($0, k "=") == 1 { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "$3" > "$sb_tmp"; then
    rm -f "$sb_tmp"
    die "could not update $3"
  fi
  mv "$sb_tmp" "$3"
}

ask() {
  printf '%s [%s]: ' "$1" "$2" >&2
  IFS= read -r _ans || _ans=""
  [ -n "$_ans" ] || _ans="$2"
  printf '%s' "$_ans"
}

TOKEN="" MACHINE="" PACK="" WORKTREES="" PONYTAIL="" GRAPHIFY="" IMAGE="" MODE="interactive"

while [ $# -gt 0 ]; do
  case "$1" in
    --token) [ $# -ge 2 ] || die "--token needs a value"; TOKEN="$2"; shift 2 ;;
    --machine) [ $# -ge 2 ] || die "--machine needs a value"; MACHINE="$2"; shift 2 ;;
    --pack) [ $# -ge 2 ] || die "--pack needs a value"; PACK="$2"; shift 2 ;;
    --worktrees) [ $# -ge 2 ] || die "--worktrees needs a value"; WORKTREES="$2"; shift 2 ;;
    --ponytail) [ $# -ge 2 ] || die "--ponytail needs a value"; PONYTAIL="$2"; shift 2 ;;
    --graphify) [ $# -ge 2 ] || die "--graphify needs a value"; GRAPHIFY="$2"; shift 2 ;;
    --image) [ $# -ge 2 ] || die "--image needs a value"; IMAGE="$2"; shift 2 ;;
    --show) MODE="show"; shift ;;
    --non-interactive) MODE="noninteractive"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

mkdir -p "$REPO_ROOT/secrets" "$REPO_ROOT/compose"
[ -f "$AGENT_ENV" ] || cp "$AGENT_EX" "$AGENT_ENV"
[ -f "$COMPOSE_ENV" ] || cp "$COMPOSE_EX" "$COMPOSE_ENV"

# never leave the terminal echo-less if interrupted during the token read
trap 'stty echo 2>/dev/null || true' EXIT

CUR_TOKEN=$(get_val KIMAKI_BOT_TOKEN "$AGENT_ENV" "")
CUR_MACHINE=$(get_val MACHINE_NAME "$AGENT_ENV" "sha2lato")
CUR_PACK=$(get_val AGENT_PACK "$AGENT_ENV" "")
CUR_WT=$(get_val KIMAKI_WORKTREES "$AGENT_ENV" "")
CUR_PONYTAIL=$(get_val PONYTAIL "$AGENT_ENV" "")
CUR_GRAPHIFY=$(get_val GRAPHIFY "$AGENT_ENV" "")
CUR_IMAGE=$(get_val SHA2LATO_AGENT_IMAGE "$COMPOSE_ENV" "sha2lato-agent:local")

if [ "$MODE" = "show" ]; then
  printf 'secrets/.env.agent:\n'
  printf '  KIMAKI_BOT_TOKEN:  %s\n' "$([ -n "$CUR_TOKEN" ] && echo set || echo 'NOT SET')"
  printf '  MACHINE_NAME:      %s\n' "$CUR_MACHINE"
  printf '  AGENT_PACK:        %s\n' "${CUR_PACK:-agents-opencode}"
  printf '  KIMAKI_WORKTREES:  %s\n' "$([ -n "$CUR_WT" ] && echo on || echo off)"
  printf '  PONYTAIL:          %s\n' "$([ "$CUR_PONYTAIL" = "0" ] && echo off || echo on)"
  printf '  GRAPHIFY:          %s\n' "$([ "$CUR_GRAPHIFY" = "0" ] && echo off || echo on)"
  printf 'compose/.env:\n'
  printf '  SHA2LATO_AGENT_IMAGE: %s (%s)\n' "$CUR_IMAGE" "$([ "$CUR_IMAGE" = "sha2lato-agent:local" ] && echo build-on-host || echo pull-from-registry)"
  exit 0
fi

if [ "$MODE" = "interactive" ] && [ ! -t 0 ]; then
  MODE="noninteractive"
fi

if [ "$MODE" = "interactive" ]; then
  printf 'sha2lato configuration — press Enter to keep the [default].\n\n' >&2

  if [ -n "$CUR_TOKEN" ]; then
    printf 'Discord bot token (Enter keeps current): ' >&2
  else
    printf 'Discord bot token: ' >&2
  fi
  stty -echo 2>/dev/null || true
  IFS= read -r TOKEN_ANS || TOKEN_ANS=""
  stty echo 2>/dev/null || true
  printf '\n' >&2
  if [ -n "$TOKEN_ANS" ]; then TOKEN="$TOKEN_ANS"; fi

  [ -n "$MACHINE" ] || MACHINE=$(ask "Machine name (Discord category becomes 'Kimaki <name>')" "$CUR_MACHINE")

  if [ -z "$PACK" ]; then
    printf 'Workflow pack:\n  1) agents-opencode (agent roster + slash commands) [default]\n  2) superpowers (plan-first methodology)\n  3) none\n' >&2
    pack_default=1
    case "$CUR_PACK" in
      superpowers) pack_default=2 ;;
      none) pack_default=3 ;;
    esac
    PACK_ANS=$(ask "Choose 1-3" "$pack_default")
    case "$PACK_ANS" in
      2) PACK="superpowers" ;;
      3) PACK="none" ;;
      *) PACK="agents-opencode" ;;
    esac
  fi

  if [ "$PACK" = "superpowers" ]; then
    WORKTREES=""
    printf '(Kimaki worktrees stay off — superpowers manages git worktrees itself)\n' >&2
  elif [ -z "$WORKTREES" ]; then
    wt_default=n
    if [ -n "$CUR_WT" ]; then wt_default=y; fi
    WT_ANS=$(ask "Kimaki worktrees (fresh git worktree per session)? y/N" "$wt_default")
    case "$WT_ANS" in y|Y|yes|YES) WORKTREES="1" ;; *) WORKTREES="" ;; esac
  fi

  if [ -z "$PONYTAIL" ]; then
    pt_default=y
    if [ "$CUR_PONYTAIL" = "0" ]; then pt_default=n; fi
    PT_ANS=$(ask "Ponytail minimal-code discipline plugin? y/N" "$pt_default")
    case "$PT_ANS" in n|N|no|NO) PONYTAIL="0" ;; *) PONYTAIL="1" ;; esac
  fi

  if [ -z "$GRAPHIFY" ]; then
    gf_default=y
    if [ "$CUR_GRAPHIFY" = "0" ]; then gf_default=n; fi
    GF_ANS=$(ask "Graphify repo knowledge graphs? y/N" "$gf_default")
    case "$GF_ANS" in n|N|no|NO) GRAPHIFY="0" ;; *) GRAPHIFY="1" ;; esac
  fi

  if [ -z "$IMAGE" ]; then
    printf 'Agent image:\n  1) build on host (default)\n  2) pull from registry (CI-published image)\n' >&2
    img_default=1
    case "$CUR_IMAGE" in
      ""|sha2lato-agent:local) img_default=1 ;;
      *) img_default=2 ;;
    esac
    IMG_ANS=$(ask "Choose 1-2" "$img_default")
    case "$IMG_ANS" in
      2) IMAGE=$(ask "Registry image ref" "${CUR_IMAGE:-ghcr.io/YOUR_USERNAME/sha2lato-agent:latest}") ;;
      *) IMAGE="sha2lato-agent:local" ;;
    esac
  fi
fi

# Fill missing non-interactive values from the current config / defaults
[ -n "$TOKEN" ] || TOKEN="$CUR_TOKEN"
[ -n "$MACHINE" ] || MACHINE="$CUR_MACHINE"
if [ -z "$PACK" ]; then PACK="$CUR_PACK"; fi
if [ -z "$PACK" ]; then PACK="agents-opencode"; fi
[ -n "$IMAGE" ] || IMAGE="$CUR_IMAGE"
case "$IMAGE" in
  local|build) IMAGE="sha2lato-agent:local" ;;
esac
if [ -z "$WORKTREES" ]; then WORKTREES="$CUR_WT"; fi
if [ -z "$PONYTAIL" ]; then PONYTAIL="$CUR_PONYTAIL"; fi
if [ -z "$PONYTAIL" ]; then PONYTAIL="1"; fi
if [ -z "$GRAPHIFY" ]; then GRAPHIFY="$CUR_GRAPHIFY"; fi
if [ -z "$GRAPHIFY" ]; then GRAPHIFY="1"; fi

case "$PACK" in
  agents-opencode|superpowers|none) ;;
  *) die "invalid --pack '$PACK' (agents-opencode|superpowers|none)" ;;
esac
case "$WORKTREES" in
  ""|off|0) WORKTREES="" ;;
  on|1) WORKTREES="1" ;;
  *) die "invalid --worktrees '$WORKTREES' (on|off)" ;;
esac
case "$PONYTAIL" in
  1|on) PONYTAIL="1" ;;
  0|off) PONYTAIL="0" ;;
  *) die "invalid --ponytail '$PONYTAIL' (on|off)" ;;
esac
case "$GRAPHIFY" in
  1|on) GRAPHIFY="1" ;;
  0|off) GRAPHIFY="0" ;;
  *) die "invalid --graphify '$GRAPHIFY' (on|off)" ;;
esac
if [ "$PACK" = "superpowers" ] && [ -n "$WORKTREES" ]; then
  printf 'note: superpowers manages git worktrees itself — forcing Kimaki worktrees off\n' >&2
  WORKTREES=""
fi
[ -n "$TOKEN" ] || die "KIMAKI_BOT_TOKEN is empty — pass --token or run interactively"

set_val KIMAKI_BOT_TOKEN "$TOKEN" "$AGENT_ENV"
set_val MACHINE_NAME "$MACHINE" "$AGENT_ENV"
set_val AGENT_PACK "$PACK" "$AGENT_ENV"
set_val KIMAKI_WORKTREES "$WORKTREES" "$AGENT_ENV"
set_val PONYTAIL "$PONYTAIL" "$AGENT_ENV"
set_val GRAPHIFY "$GRAPHIFY" "$AGENT_ENV"
set_val SHA2LATO_AGENT_IMAGE "$IMAGE" "$COMPOSE_ENV"
chmod 600 "$AGENT_ENV" 2>/dev/null || true

WT_LABEL=off
if [ -n "$WORKTREES" ]; then WT_LABEL=on; fi
PT_LABEL=off
if [ "$PONYTAIL" = "1" ]; then PT_LABEL=on; fi
GF_LABEL=off
if [ "$GRAPHIFY" = "1" ]; then GF_LABEL=on; fi

printf '\nsaved:\n'
printf '  secrets/.env.agent  token: %s | machine: %s | pack: %s | worktrees: %s\n' \
  "$([ -n "$TOKEN" ] && echo set || echo empty)" "$MACHINE" "$PACK" "$WT_LABEL"
printf '  extras              ponytail: %s | graphify: %s\n' "$PT_LABEL" "$GF_LABEL"
IMG_MODE=build-on-host
case "$IMAGE" in *:local) ;; *) IMG_MODE=pull-from-registry ;; esac
printf '  compose/.env        image: %s (%s)\n' "$IMAGE" "$IMG_MODE"
printf '\napply:  docker compose -f compose/docker-compose.yml up -d\n'
printf 'then, in Discord, run /login once to connect a model.\n'
