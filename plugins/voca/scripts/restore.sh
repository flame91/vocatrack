#!/usr/bin/env bash
# /vocab restore <word> — set status='active', clear user_rating.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

WORD="${1:-}"
[[ -z "$WORD" ]] && { echo "usage: restore.sh <word>" >&2; exit 1; }

if ! find_word "$WORD" >/dev/null; then
  echo "vocab restore: \"$WORD\" not found" >&2; exit 1
fi

lock_acquire || exit 1
trap lock_release EXIT

atomic_rewrite "$WORDS_TSV" -v w="$WORD" '
  NR == 1 { print; next }
  tolower($1) == tolower(w) { NF = 16; $12 = ""; $13 = "active"; $15 = ""; $16 = ""; print; next }
  { print }
'

echo "Restored \"$WORD\"."
