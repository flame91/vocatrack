#!/usr/bin/env bash
# /voca source remove <name>
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

NAME="${1:-}"
[[ -z "$NAME" ]] && { echo "usage: source-remove.sh <name>" >&2; exit 1; }

if ! grep -q "^${NAME} " "$SOURCES_TXT" 2>/dev/null; then
  echo "source \"$NAME\" not found."
  exit 1
fi

tmp=$(mktemp)
grep -v "^${NAME} " "$SOURCES_TXT" > "$tmp" && mv "$tmp" "$SOURCES_TXT"

lock_acquire || exit 1
trap lock_release EXIT

atomic_rewrite "$WORDS_TSV" $AWK_COL_VARS -v n="$NAME" '
  NR == 1 { print; next }
  $C_SOURCE == n { $C_SOURCE = ""; print; next }
  { print }
'

echo "Removed source \"$NAME\"."
