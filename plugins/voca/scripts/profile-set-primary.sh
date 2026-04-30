#!/usr/bin/env bash
# /voca config — set the primary language used for generated meaning/hint.
# usage: profile-set-primary.sh <ko|en|ja>
#
# Updates vocab-profile.json: sets .languages.{lang}.primary = true and clears
# all others. Validates that the requested language has spoken=true (otherwise
# the user has not opted into using it). Prints a 1-line confirmation.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-profile.sh"

LANG_CODE="${1:-}"

case "$LANG_CODE" in
  ko|en|ja) ;;
  "") echo "usage: profile-set-primary.sh <ko|en|ja>" >&2; exit 1 ;;
  *)  echo "profile-set-primary: unsupported language '$LANG_CODE' (expected ko/en/ja)" >&2; exit 1 ;;
esac

# Verify the language is marked spoken=true.
SPOKEN=$(profile_read | jq -r --arg l "$LANG_CODE" '(.languages[$l].spoken // false)')
if [[ "$SPOKEN" != "true" ]]; then
  echo "profile-set-primary: '$LANG_CODE' is not a spoken language. Run /voca level $LANG_CODE first." >&2
  exit 1
fi

# Atomic flip: clear all primaries, then set the chosen one.
profile_read \
  | jq --arg l "$LANG_CODE" '
      .languages = (
        (.languages // {})
        | with_entries(.value.primary = (.key == $l))
      )
    ' \
  | profile_write

NAME=$(profile_primary_lang_name)
echo "Primary language → $LANG_CODE ($NAME)."
