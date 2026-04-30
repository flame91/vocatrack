#!/usr/bin/env bash
# Helpers for ~/.claude/state/vocab-config.json (vocab subsystem config —
# list display, picker behavior, scan options). Coexists with legacy keys
# (extraction_model, vocab_db, etc.) and with vocab-profile.json (level data).
#
# Source: . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-config.sh"

set -uo pipefail

LIB_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_CONFIG_DIR/lib.sh"

CONFIG_PATH="${VOCAB_CONFIG_PATH:-$DB_DIR/vocab-config.json}"
CONFIG_LOCK_DIR="$DB_DIR/.vocab-config.lock.d"

config_lock_acquire() {
  local i=0
  while ! mkdir "$CONFIG_LOCK_DIR" 2>/dev/null; do
    if [[ -d "$CONFIG_LOCK_DIR" ]]; then
      local age
      age=$(( $(date +%s) - $(stat -f %m "$CONFIG_LOCK_DIR" 2>/dev/null || echo 0) ))
      (( age > 30 )) && { rmdir "$CONFIG_LOCK_DIR" 2>/dev/null || true; continue; }
    fi
    sleep 0.1
    i=$((i+1))
    (( i > 50 )) && { echo "vocab-config: lock timeout" >&2; return 1; }
  done
}
config_lock_release() { rmdir "$CONFIG_LOCK_DIR" 2>/dev/null || true; }

config_ensure_file() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo '{}' > "$CONFIG_PATH"
  fi
}

# config_get <dot.key> [default]
# Prints the scalar value (number/string/bool) or the default if missing/null.
config_get() {
  local key="$1" default="${2-}"
  if [[ ! -f "$CONFIG_PATH" ]]; then
    [[ -n "$default" ]] && printf '%s' "$default"
    return
  fi
  local val
  val=$(jq -r --arg k "$key" '
    getpath($k | split(".")) // empty
  ' "$CONFIG_PATH" 2>/dev/null)
  if [[ -z "$val" || "$val" == "null" ]]; then
    [[ -n "$default" ]] && printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}

# config_get_array <dot.key>
# Prints array entries one-per-line. Empty if key missing or not an array.
config_get_array() {
  local key="$1"
  [[ -f "$CONFIG_PATH" ]] || return 0
  jq -r --arg k "$key" '
    (getpath($k | split(".")) // []) | if type == "array" then .[] else empty end
  ' "$CONFIG_PATH" 2>/dev/null
}

# config_set <dot.key> <value>
# If <value> is valid JSON (number/bool/array/object/null/quoted string),
# stored with that type. Otherwise stored as a string.
config_set() {
  local key="$1" val="$2"
  config_lock_acquire || return 1
  config_ensure_file
  local TMP
  TMP=$(mktemp "${TMPDIR:-/tmp}/vocab-cfg.XXXXXX")
  if printf '%s' "$val" | jq . >/dev/null 2>&1; then
    jq --arg k "$key" --argjson v "$val" '
      ($k | split(".")) as $p | setpath($p; $v)
    ' "$CONFIG_PATH" > "$TMP" || { rm -f "$TMP"; config_lock_release; return 1; }
  else
    jq --arg k "$key" --arg v "$val" '
      ($k | split(".")) as $p | setpath($p; $v)
    ' "$CONFIG_PATH" > "$TMP" || { rm -f "$TMP"; config_lock_release; return 1; }
  fi
  mv "$TMP" "$CONFIG_PATH"
  config_lock_release
}

# config_unset <dot.key>
config_unset() {
  local key="$1"
  [[ -f "$CONFIG_PATH" ]] || return 0
  config_lock_acquire || return 1
  local TMP
  TMP=$(mktemp "${TMPDIR:-/tmp}/vocab-cfg.XXXXXX")
  jq --arg k "$key" 'delpaths([($k | split("."))])' "$CONFIG_PATH" > "$TMP" \
    || { rm -f "$TMP"; config_lock_release; return 1; }
  mv "$TMP" "$CONFIG_PATH"
  config_lock_release
}
