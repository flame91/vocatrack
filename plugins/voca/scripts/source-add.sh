#!/usr/bin/env bash
# /vocab source add <name> [color]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

NAME="${1:-}"
COLOR="${2:-gray}"
[[ -z "$NAME" ]] && { echo "usage: source-add.sh <name> [color]" >&2; exit 1; }

if grep -q "^${NAME} " "$SOURCES_TXT" 2>/dev/null; then
  echo "source \"$NAME\" already exists."
  exit 0
fi

printf '%s %s\n' "$NAME" "$COLOR" >> "$SOURCES_TXT"
echo "Added source \"$NAME\" ($COLOR)."
