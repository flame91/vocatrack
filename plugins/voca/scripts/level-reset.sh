#!/usr/bin/env bash
# /voca level reset — clear vocabulary level profile for one or all languages.
# Usage:
#   level-reset.sh --lang en|ja|ko|all
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-profile.sh"
. "$SCRIPT_DIR/lib-i18n.sh"

LANG_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG_ARG="${2:-}"; shift 2 ;;
    *) echo "level-reset.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done
case "$LANG_ARG" in en|ja|ko|all) ;; *) echo "level-reset.sh: --lang must be en|ja|ko|all" >&2; exit 2 ;; esac

if [[ ! -f "$PROFILE_PATH" ]]; then
  t level.reset.no_profile
  exit 0
fi

CURRENT=$(profile_read)
if [[ "$LANG_ARG" == "all" ]]; then
  printf '%s' "$CURRENT" | jq '.languages = {}' | profile_write
  t level.reset.all
else
  printf '%s' "$CURRENT" | jq --arg l "$LANG_ARG" 'del(.languages[$l])' | profile_write
  LANG_UPPER=$(printf '%s' "$LANG_ARG" | tr '[:lower:]' '[:upper:]')
  t level.reset.lang "$LANG_UPPER"
fi
