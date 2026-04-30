#!/usr/bin/env bash
# Common helpers for voca TSV-backed scripts.
# Loaded via: . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

set -uo pipefail

# --- Plugin paths (resolved once) ----------------------------------------
# PLUGIN_ROOT  — read-only plugin install dir (scripts, wordlists, messages, data)
# STATE_DIR    — per-user writable dir (vocab.tsv, profile, candidates, configs)
#
# Resolution order for STATE_DIR (first non-empty wins):
#   1. $VOCA_STATE_DIR        — explicit override
#   2. $CLAUDE_PLUGIN_DATA    — Claude Code plugin standard, survives updates
#   3. $VOCAB_DB_DIR          — legacy env var, kept for backward compat
#   4. $HOME/.claude/state    — legacy default

SCRIPT_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR_DEFAULT/.." && pwd)}"

if [[ -n "${VOCA_STATE_DIR:-}" ]]; then
  STATE_DIR="$VOCA_STATE_DIR"
elif [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
  STATE_DIR="$CLAUDE_PLUGIN_DATA"
elif [[ -n "${VOCAB_DB_DIR:-}" ]]; then
  STATE_DIR="$VOCAB_DB_DIR"
else
  STATE_DIR="$HOME/.claude/state"
fi

MESSAGES_DIR="$PLUGIN_ROOT/messages"
WORDLISTS_DIR="$PLUGIN_ROOT/scripts/wordlists"
SEEDS_DIR="$PLUGIN_ROOT/data"

# --- Backward-compatible legacy aliases (still used across scripts) -------
DB_DIR="$STATE_DIR"

WORDS_TSV="$STATE_DIR/vocab.tsv"
LOG_TSV="$STATE_DIR/vocab-candidates-log.tsv"
QUEUE_PATH="$STATE_DIR/vocab-candidates.json"
PROFILE_PATH="$STATE_DIR/vocab-profile.json"
CONFIG_PATH="$STATE_DIR/vocab-config.json"
HOOK_LOG="$STATE_DIR/vocab-hook.log"

# Tag option registries — moved from PLUGIN_ROOT (legacy) to STATE_DIR
# so users can customize without touching the read-only install.
DOMAINS_TXT="$STATE_DIR/domains.txt"
SOURCES_TXT="$STATE_DIR/sources.txt"

WORDS_HEADER=$'word\tlang\tmeaning\texample\tcontext\tsource\tdomain\tseen_count\tfirst_seen_at\tlast_seen_at\tadded_via\tuser_rating\tstatus\tuser_note\tmastered_at\tarchived_at'
LOG_HEADER=$'candidate\textracted_at\taccepted\trejected_reason\tcommand_used\thook_latency_ms\tlang_guess\tsession_hint'

mkdir -p "$STATE_DIR" 2>/dev/null || true

# Seed domains/sources from PLUGIN_ROOT/data on first run if not present in STATE_DIR.
_voca_seed_tag_files() {
  if [[ ! -f "$DOMAINS_TXT" && -f "$SEEDS_DIR/domains.default.txt" ]]; then
    cp "$SEEDS_DIR/domains.default.txt" "$DOMAINS_TXT"
  fi
  if [[ ! -f "$SOURCES_TXT" && -f "$SEEDS_DIR/sources.default.txt" ]]; then
    cp "$SEEDS_DIR/sources.default.txt" "$SOURCES_TXT"
  fi
  if [[ ! -f "$QUEUE_PATH" ]]; then
    echo '{"pending":[]}' > "$QUEUE_PATH"
  fi
}

init_db_if_missing() {
  if [[ ! -f "$WORDS_TSV" ]]; then
    printf '%s\n' "$WORDS_HEADER" > "$WORDS_TSV"
  else
    # Auto-upgrade header if outdated (e.g. 14 -> 16 columns).
    local current
    current=$(head -n 1 "$WORDS_TSV" 2>/dev/null || true)
    if [[ "$current" != "$WORDS_HEADER" ]]; then
      local tmp
      tmp=$(mktemp "${TMPDIR:-/tmp}/vocab-hdr.XXXXXX")
      { printf '%s\n' "$WORDS_HEADER"; tail -n +2 "$WORDS_TSV"; } > "$tmp" && mv "$tmp" "$WORDS_TSV"
    fi
  fi
  if [[ ! -f "$LOG_TSV" ]]; then
    printf '%s\n' "$LOG_HEADER" > "$LOG_TSV"
  fi
  _voca_seed_tag_files
}

# Sanitize a TSV field: drop \r, replace \t with space, collapse all newlines into space, strip trailing whitespace, no trailing newline.
tsv_strip() {
  awk 'BEGIN{ORS=" "} {gsub(/[\t\r]/, " "); print}' | sed -E 's/[[:space:]]+$//'
}

# Atomic rewrite. Args: file, then awk arguments (program + -v options).
atomic_rewrite() {
  local file="$1"; shift
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/vocab.XXXXXX") || return 1
  if awk -F'\t' -v OFS='\t' "$@" "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    return 1
  fi
}

# mkdir-based lock for shared mutators.
LOCK_DIR="$STATE_DIR/.vocab-write.lock.d"

lock_acquire() {
  local i=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if [[ -d "$LOCK_DIR" ]]; then
      local age
      age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
      if (( age > 30 )); then
        rmdir "$LOCK_DIR" 2>/dev/null || true
        continue
      fi
    fi
    sleep 0.1
    i=$((i+1))
    if (( i > 50 )); then
      echo "vocab: lock timeout ($LOCK_DIR)" >&2
      return 1
    fi
  done
}

lock_release() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

# Look up one row by word (case-insensitive). Prints matching TSV line. Returns 1 if not found.
find_word() {
  local w="$1"
  awk -F'\t' -v w="$w" '
    NR==1 { next }
    tolower($1) == tolower(w) { print; found=1; exit }
    END { exit (found?0:1) }
  ' "$WORDS_TSV"
}

today() {
  date -u +%Y-%m-%d
}

init_db_if_missing
