#!/usr/bin/env bash
# /voca domain add <name> [color]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

NAME="${1:-}"
COLOR="${2:-gray}"
[[ -z "$NAME" ]] && { echo "usage: domain-add.sh <name> [color]" >&2; exit 1; }

if grep -q "^${NAME} " "$DOMAINS_TXT" 2>/dev/null; then
  echo "domain \"$NAME\" already exists."
  exit 0
fi

printf '%s %s\n' "$NAME" "$COLOR" >> "$DOMAINS_TXT"
echo "Added domain \"$NAME\" ($COLOR)."
