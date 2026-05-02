#!/usr/bin/env bash
# /voca — internal helper. Replace the domain JSON for an existing word.
# usage: set-domain.sh <word> <domain_json>
# ex:    set-domain.sh recall '["ai","data","science"]'
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

WORD="${1:-}"
DOMAIN_JSON="${2:-}"

if [[ -z "$WORD" || -z "$DOMAIN_JSON" ]]; then
  echo "usage: set-domain.sh <word> <domain_json>" >&2
  exit 1
fi

# Validate JSON
if ! echo "$DOMAIN_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "set-domain: <domain_json> must be a JSON array (got: $DOMAIN_JSON)" >&2
  exit 1
fi

if ! find_word "$WORD" >/dev/null; then
  echo "set-domain: \"$WORD\" not found" >&2
  exit 1
fi

# Sanitize: tabs/newlines could not appear in valid JSON arrays, but be safe.
SAFE=$(printf '%s' "$DOMAIN_JSON" | tr -d '\t\r\n')

lock_acquire || exit 1
trap lock_release EXIT

atomic_rewrite "$WORDS_TSV" $AWK_COL_VARS -v w="$WORD" -v d="$SAFE" '
  NR == 1 { print; next }
  tolower($C_WORD) == tolower(w) { NF = NCOLS; $C_DOMAIN = d; print; next }
  { print }
'

echo "Reclassified \"$WORD\" → $SAFE."
