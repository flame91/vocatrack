#!/usr/bin/env bash
# /voca rate <word> <memorized|learning|unsure> [note]
# memorized → also auto-promote status to 'mastered'.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

WORD="${1:-}"
RATING="${2:-}"
NOTE="${3:-}"

if [[ -z "$WORD" || -z "$RATING" ]]; then
  echo "usage: rate.sh <word> <memorized|learning|unsure> [note]" >&2
  exit 1
fi
case "$RATING" in
  memorized|learning|unsure) ;;
  *) echo "rating must be memorized|learning|unsure (got: $RATING)" >&2; exit 1 ;;
esac

EXISTING=$(find_word "$WORD" || true)
if [[ -z "$EXISTING" ]]; then
  echo "voca rate: \"$WORD\" not found" >&2
  exit 1
fi

NOTE_CLEAN=$(printf '%s' "$NOTE" | tsv_strip)

lock_acquire || exit 1
trap lock_release EXIT

TODAY=$(today)
atomic_rewrite "$WORDS_TSV" $AWK_COL_VARS \
  -v w="$WORD" -v r="$RATING" -v n="$NOTE_CLEAN" -v t="$TODAY" '
  NR == 1 { print; next }
  tolower($C_WORD) == tolower(w) {
    NF = NCOLS
    $C_RATING = r
    if (r == "memorized") { $C_STATUS = "mastered"; $C_MASTERED_AT = t }
    if (n != "") $C_NOTE = n
    print
    next
  }
  { print }
'

if [[ "$RATING" == "memorized" ]]; then
  echo "Rated \"$WORD\" memorized → mastered."
else
  echo "Rated \"$WORD\" $RATING."
fi
