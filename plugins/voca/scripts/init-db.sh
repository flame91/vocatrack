#!/usr/bin/env bash
# Initialize TSV files if missing. Idempotent.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

echo "vocab: $WORDS_TSV ($(wc -l < "$WORDS_TSV" | tr -d ' ') lines)"
echo "vocab: $LOG_TSV ($(wc -l < "$LOG_TSV" | tr -d ' ') lines)"
