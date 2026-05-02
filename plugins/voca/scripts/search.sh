#!/usr/bin/env bash
# /voca search <query> — case-insensitive grep across word + meaning + example + context.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

Q="${1:-}"
[[ -z "$Q" ]] && { echo "usage: search.sh <query>" >&2; exit 1; }

ROWS=$(awk -F'\t' -v q="$Q" '
  NR == 1 { next }
  BEGIN { qs = tolower(q) }
  {
    line = tolower($1 "\t" $3 "\t" $4 "\t" $5)
    if (index(line, qs) > 0) print
  }
' "$WORDS_TSV")

if [[ -z "$ROWS" ]]; then
  echo "(no matches for \"$Q\")"
  exit 0
fi

{
  echo $'word\tlang\tmeaning\tstatus\trating'
  printf '%s\n' "$ROWS" | awk -F'\t' -v OFS='\t' '{
    m = $3; if (length(m) > 50) m = substr(m, 1, 50)
    st = ($13 == "" ? "active" : $13)
    rt = ($12 == "" ? "-" : $12)
    print $1, ($2 == "" ? "-" : $2), m, st, rt
  }'
} | column -t -s $'\t'
