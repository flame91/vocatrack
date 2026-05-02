#!/usr/bin/env bash
# /voca domain remove <name>
# Strips the option from domains.txt and from any rows that have it in domain JSON array.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

NAME="${1:-}"
[[ -z "$NAME" ]] && { echo "usage: domain-remove.sh <name>" >&2; exit 1; }

if ! grep -q "^${NAME} " "$DOMAINS_TXT" 2>/dev/null; then
  echo "domain \"$NAME\" not found."
  exit 1
fi

# Remove from registry
tmp=$(mktemp)
grep -v "^${NAME} " "$DOMAINS_TXT" > "$tmp" && mv "$tmp" "$DOMAINS_TXT"

# Strip from words.tsv domain JSON arrays
lock_acquire || exit 1
trap lock_release EXIT

atomic_rewrite "$WORDS_TSV" $AWK_COL_VARS -v n="$NAME" '
  NR == 1 { print; next }
  {
    d = $C_DOMAIN
    if (d == "" || d == "[]") { print; next }
    cmd = "printf %s " q(d) " | jq -c --arg n " q(n) " \047map(select(. != $n))\047 2>/dev/null"
    if ((cmd | getline result) > 0) {
      d = result
    }
    close(cmd)
    if (d == "[]" || d == "") d = "[]"
    $C_DOMAIN = d
    print
  }
  function q(s) { gsub(/\047/, "\047\\\047\047", s); return "\047" s "\047" }
'

echo "Removed domain \"$NAME\"."
