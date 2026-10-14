#!/bin/sh
# sha2lato age overlay — optional encrypted backup of your secrets/*.env
# files that you CAN safely commit to the repo.
#
# The private key NEVER goes in the repo. Default location:
#   ~/.config/sha2lato/age.key   (override with AGE_KEYFILE)
# The recipient (public key) is read from $AGE_RECIPIENT or
# secrets/age/recipient (committable — it is not secret).
#
# Usage:
#   deploy/age.sh keygen                 create keypair, save recipient
#   deploy/age.sh encrypt [file...]      secrets/.env.* -> secrets/age/*.age
#   deploy/age.sh decrypt [file...]      secrets/age/*.age -> secrets/
#
# Requires: age — https://github.com/FiloSottile/age

set -e

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SECRETS_DIR="$REPO_ROOT/secrets"
AGE_DIR="$SECRETS_DIR/age"
KEYFILE="${AGE_KEYFILE:-$HOME/.config/sha2lato/age.key}"

die() { echo "error: $*" >&2; exit 1; }

need_age() {
  command -v age >/dev/null 2>&1 || die "age is not installed — see https://github.com/FiloSottile/age"
}

recipient() {
  if [ -n "$AGE_RECIPIENT" ]; then echo "$AGE_RECIPIENT"; return; fi
  if [ -f "$AGE_DIR/recipient" ]; then head -n 1 "$AGE_DIR/recipient"; return; fi
  die "no recipient: set AGE_RECIPIENT or create secrets/age/recipient (run: $0 keygen)"
}

keygen() {
  need_age
  mkdir -p "$(dirname "$KEYFILE")" "$AGE_DIR"
  if [ -f "$KEYFILE" ]; then die "key already exists at $KEYFILE (delete it first to regenerate)"; fi
  age-keygen -o "$KEYFILE" 2>/dev/null
  chmod 600 "$KEYFILE"
  REC=$(age-keygen -y "$KEYFILE")
  echo "$REC" > "$AGE_DIR/recipient"
  echo "private key: $KEYFILE   (keep secret — never commit)"
  echo "recipient:   $REC"
  echo "recipient saved to secrets/age/recipient (safe to commit)"
}

encrypt_one() {
  src="$1"
  base=$(basename "$src")
  age -r "$(recipient)" -o "$AGE_DIR/$base.age" "$src"
  echo "encrypted: $src -> $AGE_DIR/$base.age"
}

decrypt_one() {
  enc="$1"
  base=$(basename "$enc" .age)
  if [ ! -f "$KEYFILE" ]; then die "private key not found at $KEYFILE (set AGE_KEYFILE?)"; fi
  age -d -i "$KEYFILE" -o "$SECRETS_DIR/$base" "$enc"
  chmod 600 "$SECRETS_DIR/$base"
  echo "decrypted: $enc -> $SECRETS_DIR/$base"
}

case "${1:-}" in
  keygen)
    keygen
    ;;
  encrypt)
    shift
    if [ $# -eq 0 ]; then set -- "$SECRETS_DIR"/.env.*; fi
    for f in "$@"; do
      case "$f" in *.example) continue ;; esac
      if [ -f "$f" ]; then encrypt_one "$f"; fi
    done
    ;;
  decrypt)
    shift
    if [ $# -eq 0 ]; then set -- "$AGE_DIR"/*.age; fi
    for f in "$@"; do
      case "$f" in *.example.age) continue ;; esac
      if [ -f "$f" ]; then decrypt_one "$f"; fi
    done
    ;;
  *)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
