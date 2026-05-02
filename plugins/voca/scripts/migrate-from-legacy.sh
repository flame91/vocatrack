#!/usr/bin/env bash
# One-time migration: copy legacy ~/.claude/state/voca* state files into the
# plugin's STATE_DIR. Safe re-run — copies only when source is newer or target
# is missing. Use --dry-run to preview without writing.
#
# Usage:
#   migrate-from-legacy.sh            # apply
#   migrate-from-legacy.sh --dry-run  # preview only

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

LEGACY="$HOME/.claude/state"

if [[ "$LEGACY" == "$STATE_DIR" ]]; then
  echo "STATE_DIR already points at legacy location — nothing to migrate."
  echo "  STATE_DIR=$STATE_DIR"
  exit 0
fi

declare -A FILE_MAP=(
  [vocab.tsv]=voca.tsv
  [vocab-profile.json]=voca-profile.json
  [vocab-config.json]=voca-config.json
  [vocab-candidates.json]=voca-candidates.json
  [vocab-candidates-log.tsv]=voca-candidates-log.tsv
  [vocab-hook.log]=voca-hook.log
)

found=0
for old_name in "${!FILE_MAP[@]}"; do
  new_name="${FILE_MAP[$old_name]}"
  src="$LEGACY/$old_name"
  dst="$STATE_DIR/$new_name"
  [[ -f "$src" ]] || continue
  found=$((found + 1))

  if [[ ! -f "$dst" ]]; then
    action="COPY (new)"
  elif [[ "$src" -nt "$dst" ]]; then
    action="OVERWRITE (legacy newer)"
  else
    action="SKIP (target newer or equal)"
  fi

  printf '  %-30s → %-30s %s\n' "$old_name" "$new_name" "$action"

  if (( DRY == 0 )) && [[ "$action" != SKIP* ]]; then
    cp -p "$src" "$dst"
  fi
done

if (( found == 0 )); then
  echo "No legacy state found at $LEGACY — nothing to migrate."
  exit 0
fi

if (( DRY == 1 )); then
  echo
  echo "(dry-run) re-run without --dry-run to apply."
else
  echo
  echo "Migration complete. Legacy files at $LEGACY are NOT removed —"
  echo "verify the new state under $STATE_DIR, then delete manually if desired."
fi
