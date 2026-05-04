#!/usr/bin/env bash
# i18n helper for voca scripts. Loaded after lib.sh:
#   . "$SCRIPT_DIR/lib.sh"
#   . "$SCRIPT_DIR/lib-i18n.sh"
#
# Locale resolution (first non-empty wins):
#   1. $VOCA_LOCALE                       — explicit override (ko|en|ja)
#   2. voca-profile.json primary language — set via /voca config (primary=true)
#   3. $LANG / $LC_ALL                    — system locale (e.g. ko_KR.UTF-8 -> ko)
#   4. en                                 — fallback
#
# Profile primary outranks $LANG so users on neutral locales (C.UTF-8, en_US)
# get their chosen UI language without needing to export VOCA_LOCALE.
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
  # 1. Explicit override.
  case "${VOCA_LOCALE:-}" in
    ko|en|ja) printf '%s' "$VOCA_LOCALE"; return ;;
  esac
  # 2. Profile primary language (set via /voca config).
  if [[ -f "${PROFILE_PATH:-}" ]] && command -v jq >/dev/null 2>&1; then
    local p
    p=$(jq -r '
      (.languages // {}) | to_entries
      | map(select(.value.primary == true))
      | (.[0].key // "")
    ' "$PROFILE_PATH" 2>/dev/null)
    case "$p" in
      ko|en|ja) printf '%s' "$p"; return ;;
    esac
  fi
  # 3. System locale.
  local raw="${LC_ALL:-${LANG:-}}"
  raw="${raw%%.*}"      # ko_KR.UTF-8 -> ko_KR
  raw="${raw%%_*}"      # ko_KR -> ko
  case "$raw" in
    ko|en|ja) printf '%s' "$raw"; return ;;
  esac
  # 4. Fallback.
  printf '%s' "en"
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
