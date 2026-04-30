#!/usr/bin/env bash
# /voca queue clear — silently empty the queue (no Candidates Log write).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

echo '{"pending":[]}' > "$QUEUE_PATH"
echo "Queue cleared."
