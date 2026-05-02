#!/usr/bin/env bash
# /voca search <query> — case-insensitive grep across word + meaning + example + context.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

Q="${1:-}"
[[ -z "$Q" ]] && { echo "usage: search.sh <query>" >&2; exit 1; }

ROWS=$(awk -F'\t' $AWK_COL_VARS -v q="$Q" '
  NR == 1 { next }
  BEGIN { qs = tolower(q) }
  {
    line = tolower($C_WORD "\t" $C_MEANING "\t" $C_EXAMPLE "\t" $C_CONTEXT)
    if (index(line, qs) > 0) print
  }
' "$WORDS_TSV")

if [[ -z "$ROWS" ]]; then
  echo "(no matches for \"$Q\")"
  exit 0
fi

{
  echo $'word\tlang\tmeaning\tstatus\trating'
  printf '%s\n' "$ROWS" | awk -F'\t' -v OFS='\t' $AWK_COL_VARS '{
    m = $C_MEANING; if (length(m) > 50) m = substr(m, 1, 50)
    st = ($C_STATUS == "" ? "active" : $C_STATUS)
    rt = ($C_RATING == "" ? "-" : $C_RATING)
    print $C_WORD, ($C_LANG == "" ? "-" : $C_LANG), m, st, rt
  }'
} | column -t -s $'\t'
