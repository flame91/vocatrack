#!/usr/bin/env bash
# /voca source list — show source options from sources.txt.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

if [[ ! -f "$SOURCES_TXT" ]]; then
  echo "(no sources defined; create $SOURCES_TXT)"
  exit 0
fi

{
  echo "name color"
  cat "$SOURCES_TXT"
} | column -t
