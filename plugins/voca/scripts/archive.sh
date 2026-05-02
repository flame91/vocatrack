#!/usr/bin/env bash
# /voca archive <word> — set status='archived'.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

WORD="${1:-}"
[[ -z "$WORD" ]] && { echo "usage: archive.sh <word>" >&2; exit 1; }

if ! find_word "$WORD" >/dev/null; then
  echo "voca archive: \"$WORD\" not found" >&2; exit 1
fi

lock_acquire || exit 1
trap lock_release EXIT

TODAY=$(today)
atomic_rewrite "$WORDS_TSV" $AWK_COL_VARS -v w="$WORD" -v t="$TODAY" '
  NR == 1 { print; next }
  tolower($C_WORD) == tolower(w) { NF = NCOLS; $C_STATUS = "archived"; $C_ARCHIVED_AT = t; print; next }
  { print }
'

echo "Archived \"$WORD\"."
