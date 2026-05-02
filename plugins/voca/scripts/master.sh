#!/usr/bin/env bash
# /voca master <word> — set status='mastered' (manual promotion).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

WORD="${1:-}"
[[ -z "$WORD" ]] && { echo "usage: master.sh <word>" >&2; exit 1; }

if ! find_word "$WORD" >/dev/null; then
  echo "voca master: \"$WORD\" not found" >&2; exit 1
fi

lock_acquire || exit 1
trap lock_release EXIT

TODAY=$(today)
atomic_rewrite "$WORDS_TSV" -v w="$WORD" -v t="$TODAY" '
  NR == 1 { print; next }
  tolower($1) == tolower(w) { NF = 16; $13 = "mastered"; $15 = t; print; next }
  { print }
'

echo "Mastered \"$WORD\"."
