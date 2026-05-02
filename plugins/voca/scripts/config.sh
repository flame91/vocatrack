#!/usr/bin/env bash
# /voca config — CLI entry for voca subsystem config.
#   show                    — print full config (jq pretty)
#   get <key>               — print one value (dot notation)
#   set <key> <value>       — set a value (auto-detect JSON vs string)
#   reset <key>             — delete one key
#   reset --scope           — delete only list/picker/scan (preserve legacy + level keys)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-config.sh"

usage() {
  cat <<'EOF' >&2
usage: config.sh <subcommand>
  show
  get <key>
  set <key> <value>
  reset <key>
  reset --scope          (clears list/picker/scan only)
EOF
  exit 1
}

cmd="${1:-show}"
shift || true

case "$cmd" in
  show)
    if [[ -f "$CONFIG_PATH" ]]; then
      jq . "$CONFIG_PATH"
    else
      echo '{}'
    fi
    ;;
  get)
    [[ $# -eq 1 ]] || usage
    val=$(config_get "$1")
    if [[ -z "$val" ]]; then
      # try array
      arr=$(config_get_array "$1")
      [[ -n "$arr" ]] && printf '%s\n' "$arr"
    else
      printf '%s\n' "$val"
    fi
    ;;
  set)
    [[ $# -eq 2 ]] || usage
    config_set "$1" "$2"
    echo "set $1 = $2"
    ;;
  reset)
    if [[ "${1:-}" == "--scope" ]]; then
      config_lock_acquire
      config_ensure_file
      TMP=$(mktemp "${TMPDIR:-/tmp}/voca-cfg.XXXXXX")
      jq 'del(.list, .picker, .scan)' "$CONFIG_PATH" > "$TMP" && mv "$TMP" "$CONFIG_PATH"
      config_lock_release
      echo "reset list/picker/scan (legacy + level keys preserved)"
    elif [[ $# -eq 1 ]]; then
      config_unset "$1"
      echo "reset $1"
    else
      usage
    fi
    ;;
  *) usage ;;
esac
