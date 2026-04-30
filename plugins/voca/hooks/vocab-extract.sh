#!/usr/bin/env bash
# Stop hook (entry point).
#
# Kicks off the async extractor in the background for the latest response.
# Stop hook schema does not allow additionalContext, so this hook never writes
# to stdout — the queue file is the source of truth and /vocab queue surfaces it.
#
# Recursion guard: if VOCAB_HOOK_RUNNING is set, this is a nested claude
# session spawned by the extractor — exit immediately.

set -uo pipefail

if [[ "${VOCAB_HOOK_RUNNING:-0}" == "1" ]]; then
  exit 0
fi

# Resolve plugin paths via lib.sh (handles CLAUDE_PLUGIN_ROOT/DATA + legacy fallback).
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_GUESS="${CLAUDE_PLUGIN_ROOT:-$(cd "$HOOK_DIR/.." && pwd)}"
. "$PLUGIN_ROOT_GUESS/scripts/lib.sh"

LOG="$HOOK_LOG"
ASYNC="$HOOK_DIR/vocab-extract-async.sh"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" && -x "$ASYNC" ]]; then
  nohup bash "$ASYNC" "$TRANSCRIPT" </dev/null >>"$LOG" 2>&1 &
  disown 2>/dev/null || true
fi

exit 0
