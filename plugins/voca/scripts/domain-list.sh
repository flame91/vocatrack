#!/usr/bin/env bash
# /voca domain list — show domain options from domains.txt.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

if [[ ! -f "$DOMAINS_TXT" ]]; then
  echo "(no domains defined; create $DOMAINS_TXT)"
  exit 0
fi

{
  echo "name color"
  cat "$DOMAINS_TXT"
} | column -t
