#!/usr/bin/env bash
# /voca add — stdin JSON with inferred properties.
# Expected JSON:
#   {
#     "word": "ephemeral",
#     "lang": "en",
#     "meaning": "...",
#     "example": "...",
#     "context": "...",
#     "source": "software",
#     "domain": ["software"],
#     "added_via": "manual"   // or "auto-hook" | "review" | "import"
#   }
# All fields optional except "word". On dup (case-insensitive), seen_count+=1, last_seen_at=today,
# and (if context provided & previously empty) context is filled.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

JSON=$(cat)
if [[ -z "$JSON" ]]; then
  echo "voca add: empty stdin (expected JSON)" >&2
  exit 1
fi

WORD=$(printf '%s' "$JSON" | jq -r '.word // empty' | tsv_strip)
if [[ -z "$WORD" ]]; then
  echo "voca add: missing 'word' in JSON" >&2
  exit 1
fi

LANG=$(printf '%s' "$JSON" | jq -r '.lang // ""' | tsv_strip)
MEANING=$(printf '%s' "$JSON" | jq -r '.meaning // ""' | tsv_strip)
EXAMPLE=$(printf '%s' "$JSON" | jq -r '.example // ""' | tsv_strip)
CONTEXT=$(printf '%s' "$JSON" | jq -r '.context // ""' | tsv_strip)
SOURCE=$(printf '%s' "$JSON" | jq -r '.source // ""' | tsv_strip)
DOMAIN=$(printf '%s' "$JSON" | jq -c '.domain // []' | tsv_strip)
ADDED_VIA=$(printf '%s' "$JSON" | jq -r '.added_via // "manual"' | tsv_strip)

TODAY=$(today)

lock_acquire || exit 1
trap lock_release EXIT

# Check duplicate
EXISTING=$(find_word "$WORD" || true)

if [[ -n "$EXISTING" ]]; then
  # Update seen_count, last_seen_at, optionally fill empty context
  atomic_rewrite "$WORDS_TSV" \
    -v w="$WORD" -v t="$TODAY" -v ctx="$CONTEXT" '
    NR == 1 { print; next }
    tolower($1) == tolower(w) {
      $8 = ($8 == "" ? 2 : $8 + 1)
      $10 = t
      if ($5 == "" && ctx != "") $5 = ctx
      print
      next
    }
    { print }
  '
  OLD_MEANING=$(printf '%s' "$EXISTING" | awk -F'\t' '{print $3}')
  echo "Updated \"$WORD\" — ${OLD_MEANING:-(no meaning)} (seen again)."
else
  printf '%s\n' "$WORD"$'\t'"$LANG"$'\t'"$MEANING"$'\t'"$EXAMPLE"$'\t'"$CONTEXT"$'\t'"$SOURCE"$'\t'"$DOMAIN"$'\t1\t'"$TODAY"$'\t'"$TODAY"$'\t'"$ADDED_VIA"$'\t\tactive\t\t\t' >> "$WORDS_TSV"
  echo "Added \"$WORD\" — ${MEANING:-(no meaning)}."
fi
