#!/usr/bin/env bash
# /voca restore <word> — set status='active', clear user_rating.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

WORD="${1:-}"
[[ -z "$WORD" ]] && { echo "usage: restore.sh <word>" >&2; exit 1; }

if ! find_word "$WORD" >/dev/null; then
  echo "voca restore: \"$WORD\" not found" >&2; exit 1
fi

lock_acquire || exit 1
trap lock_release EXIT

atomic_rewrite "$WORDS_TSV" $AWK_COL_VARS -v w="$WORD" '
  NR == 1 { print; next }
  tolower($C_WORD) == tolower(w) { NF = NCOLS; $C_RATING = ""; $C_STATUS = "active"; $C_MASTERED_AT = ""; $C_ARCHIVED_AT = ""; print; next }
  { print }
'

echo "Restored \"$WORD\"."
