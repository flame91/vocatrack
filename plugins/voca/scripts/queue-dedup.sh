#!/usr/bin/env bash
# Re-filter pending candidates against current voca.tsv, removing stale entries.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
init_db_if_missing

QUEUE="$QUEUE_PATH"
[[ -f "$QUEUE" ]] || exit 0

SKIP=$(
  { [[ -f "$WORDS_TSV" ]] && awk -F'\t' 'NR>1 && $1!="" {print tolower($1)}' "$WORDS_TSV";
    [[ -f "$LOG_TSV" ]] && awk -F'\t' 'NR>1 && $1!="" && $4=="user marked as already known via picker" {print tolower($1)}' "$LOG_TSV";
  } | sort -u
)
[[ -z "$SKIP" ]] && exit 0

BEFORE=$(jq '.pending | length' "$QUEUE" 2>/dev/null)
TMP=$(mktemp)
jq --arg s "$SKIP" '
  ($s | split("\n") | map(select(length > 0))) as $skip |
  .pending |= [ .[] | select((.word | ascii_downcase) as $w | ($skip | index($w)) | not) ]
' "$QUEUE" > "$TMP" 2>/dev/null && mv "$TMP" "$QUEUE" || rm -f "$TMP"
AFTER=$(jq '.pending | length' "$QUEUE" 2>/dev/null)

if [[ "$BEFORE" != "$AFTER" ]]; then
  printf 'dedup: %s -> %s\n' "$BEFORE" "$AFTER"
fi
