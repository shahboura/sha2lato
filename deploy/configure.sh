#!/bin/sh
# sha2lato configure — one place to set the box's knobs.
#
# Interactive:      ./deploy/configure.sh
# Non-interactive:  ./deploy/configure.sh --token <t> [--machine <m>]
#                   [--pack none|agents-opencode|superpowers]
#                   [--worktrees on|off] [--image <ref>]
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

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "error: $*" >&2; exit 1; }

get_val() {
  v=$(grep -E "^$1=" "$2" 2>/dev/null | tail -n 1 | cut -d '=' -f 2- || true)
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

TOKEN="" MACHINE="" PACK="" WORKTREES="" IMAGE="" MODE="interactive"

while [ $# -gt 0 ]; do
  case "$1" in
    --token) [ $# -ge 2 ] || die "--token needs a value"; TOKEN="$2"; shift 2 ;;
    --machine) [ $# -ge 2 ] || die "--machine needs a value"; MACHINE="$2"; shift 2 ;;
    --pack) [ $# -ge 2 ] || die "--pack needs a value"; PACK="$2"; shift 2 ;;
    --worktrees) [ $# -ge 2 ] || die "--worktrees needs a value"; WORKTREES="$2"; shift 2 ;;
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
CUR_IMAGE=$(get_val SHA2LATO_AGENT_IMAGE "$COMPOSE_ENV" "sha2lato-agent:local")

if [ "$MODE" = "show" ]; then
  printf 'secrets/.env.agent:\n'
  printf '  KIMAKI_BOT_TOKEN:  %s\n' "$([ -n "$CUR_TOKEN" ] && echo set || echo 'NOT SET')"
  printf '  MACHINE_NAME:      %s\n' "$CUR_MACHINE"
  printf '  AGENT_PACK:        %s\n' "${CUR_PACK:-(none)}"
  printf '  KIMAKI_WORKTREES:  %s\n' "$([ -n "$CUR_WT" ] && echo on || echo off)"
  printf 'compose/.env:\n'
  printf '  SHA2LATO_AGENT_IMAGE: %s\n' "$CUR_IMAGE"
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
    printf 'Workflow pack:\n  1) none\n  2) agents-opencode (agent roster + slash commands)\n  3) superpowers (plan-first methodology)\n' >&2
    pack_default=1
    case "$CUR_PACK" in
      agents-opencode) pack_default=2 ;;
      superpowers) pack_default=3 ;;
    esac
    PACK_ANS=$(ask "Choose 1-3" "$pack_default")
    case "$PACK_ANS" in
      2) PACK="agents-opencode" ;;
      3) PACK="superpowers" ;;
      *) PACK="" ;;
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
fi

# Fill missing non-interactive values from the current config
[ -n "$TOKEN" ] || TOKEN="$CUR_TOKEN"
[ -n "$MACHINE" ] || MACHINE="$CUR_MACHINE"
[ -n "$PACK" ] || PACK="$CUR_PACK"
[ -n "$IMAGE" ] || IMAGE="$CUR_IMAGE"
if [ -z "$WORKTREES" ]; then WORKTREES="$CUR_WT"; fi

case "$PACK" in
  ""|agents-opencode|superpowers) ;;
  none) PACK="" ;;
  *) die "invalid --pack '$PACK' (none|agents-opencode|superpowers)" ;;
esac
case "$WORKTREES" in
  ""|off|0) WORKTREES="" ;;
  on|1) WORKTREES="1" ;;
  *) die "invalid --worktrees '$WORKTREES' (on|off)" ;;
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
set_val SHA2LATO_AGENT_IMAGE "$IMAGE" "$COMPOSE_ENV"
chmod 600 "$AGENT_ENV" 2>/dev/null || true

WT_LABEL=off
if [ -n "$WORKTREES" ]; then WT_LABEL=on; fi
printf '\nsaved:\n'
printf '  secrets/.env.agent  token: %s | machine: %s | pack: %s | worktrees: %s\n' \
  "$([ -n "$TOKEN" ] && echo set || echo empty)" "$MACHINE" "${PACK:-(none)}" "$WT_LABEL"
printf '  compose/.env        image: %s\n' "$IMAGE"
printf '\napply:  docker compose -f compose/docker-compose.yml up -d\n'
printf 'then, in Discord, run /login once to connect a model.\n'
