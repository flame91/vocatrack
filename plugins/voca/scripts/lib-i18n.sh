#!/usr/bin/env bash
# i18n helper for voca scripts. Loaded after lib.sh:
#   . "$SCRIPT_DIR/lib.sh"
#   . "$SCRIPT_DIR/lib-i18n.sh"
#
# Locale resolution (first non-empty wins):
#   1. $VOCA_LOCALE          — explicit override (ko|en|ja)
#   2. $LANG / $LC_ALL       — system locale (e.g. ko_KR.UTF-8 -> ko)
#   3. en                    — fallback
#
# Usage:
#   t profile.empty                  # plain lookup
#   t stage1.result EN 4500 1100 18000   # printf-style placeholders ($1, $2, ...)

# shellcheck disable=SC2034

set -uo pipefail

if [[ -z "${MESSAGES_DIR:-}" ]]; then
  echo "lib-i18n: MESSAGES_DIR not set — source lib.sh first" >&2
  return 1 2>/dev/null || exit 1
fi

_voca_resolve_locale() {
  local raw="${VOCA_LOCALE:-${LC_ALL:-${LANG:-}}}"
  raw="${raw%%.*}"      # ko_KR.UTF-8 -> ko_KR
  raw="${raw%%_*}"      # ko_KR -> ko
  case "$raw" in
    ko|en|ja) printf '%s' "$raw" ;;
    *) printf '%s' "en" ;;
  esac
}

VOCA_LOCALE_RESOLVED="$(_voca_resolve_locale)"

# Look up a message key. Falls back to en.tsv, then to the literal key.
# All TSV files: tab-separated `key<TAB>printf-format`.
# Use printf escapes (%s, %d) for placeholders; pass values as positional args.
_voca_lookup() {
  local key="$1"
  local locale="$2"
  local file="$MESSAGES_DIR/$locale.tsv"
  [[ -f "$file" ]] || return 1
  awk -F'\t' -v k="$key" '
    $1 == k { sub(/^[^\t]*\t/, ""); print; found=1; exit }
    END     { exit (found ? 0 : 1) }
  ' "$file"
}

t() {
  local key="$1"; shift || true
  local fmt
  fmt=$(_voca_lookup "$key" "$VOCA_LOCALE_RESOLVED" 2>/dev/null) \
    || fmt=$(_voca_lookup "$key" "en" 2>/dev/null) \
    || fmt="$key"
  # printf interprets %s, %d, etc. — escape literal % as %%.
  # shellcheck disable=SC2059
  printf "$fmt" "$@"
  printf '\n'
}

# Variant that suppresses the trailing newline (for inline composition).
ti() {
  local key="$1"; shift || true
  local fmt
  fmt=$(_voca_lookup "$key" "$VOCA_LOCALE_RESOLVED" 2>/dev/null) \
    || fmt=$(_voca_lookup "$key" "en" 2>/dev/null) \
    || fmt="$key"
  # shellcheck disable=SC2059
  printf "$fmt" "$@"
}
