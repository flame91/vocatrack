#!/usr/bin/env bash
# /voca scan launcher. Replaces the inline lock-check + spawn snippet in SKILL.md
# so the model can pass output through verbatim instead of resolving message keys.
#
# Behavior:
#   - If extract lock exists and is < 120s old → print [scan.already_running], skip spawn.
#   - Otherwise spawn voca-extract-async.sh in background, print [scan.spawned].
#     If the queue already has pending entries, append [scan.status_queue] with the count.
#
# Output: 1-2 localized lines on stdout. Exit 0 in all normal cases.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-i18n.sh"

EXTRACT_LOCK="$STATE_DIR/.voca-extract.lock.d"

if [[ -d "$EXTRACT_LOCK" ]]; then
  mtime=$(stat -c %Y "$EXTRACT_LOCK" 2>/dev/null || stat -f %m "$EXTRACT_LOCK" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - mtime ))
  if (( age < 120 )); then
    t scan.already_running
    exit 0
  fi
fi

LATEST=$(ls -t "$HOME/.claude/projects/-${PWD//\//-}"/*.jsonl 2>/dev/null | head -n 1)
[[ -z "$LATEST" ]] && LATEST=$(ls -t "$HOME/.claude/projects"/*/*.jsonl 2>/dev/null | head -n 1)

if [[ -z "$LATEST" || ! -f "$LATEST" ]]; then
  echo "scan: no transcript file found under ~/.claude/projects/" >&2
  exit 1
fi

nohup bash "$PLUGIN_ROOT/hooks/voca-extract-async.sh" "$LATEST" full \
  >>"$HOOK_LOG" 2>&1 < /dev/null &
disown 2>/dev/null || true

t scan.spawned

if [[ -f "$QUEUE_PATH" ]]; then
  count=$(jq '.pending | length' "$QUEUE_PATH" 2>/dev/null || echo 0)
  if (( count > 0 )); then
    t scan.status_queue "$count"
  fi
fi
