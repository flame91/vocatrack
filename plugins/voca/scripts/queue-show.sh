#!/usr/bin/env bash
# /voca queue candidates — show pending candidate queue.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

if [[ ! -f "$QUEUE_PATH" ]]; then
  echo "(empty queue)"
  exit 0
fi

COUNT=$(jq '.pending | length' "$QUEUE_PATH" 2>/dev/null || echo 0)
if [[ "$COUNT" -eq 0 ]]; then
  echo "(empty queue)"
  exit 0
fi

{
  echo "word|lang|hint|extracted_at"
  jq -r '.pending[] | [.word, (.lang // "-"), ((.hint // "-") | .[0:50]), (.extracted_at // "-")] | join("|")' "$QUEUE_PATH"
} | column -t -s '|'

echo
echo "Total: $COUNT"
