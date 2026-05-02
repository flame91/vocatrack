#!/usr/bin/env bash
# Async extractor — runs in the background, spawned by voca-extract.sh.
# Calls `claude -p` with the configured scan model (default Haiku) to extract
# candidate words from the latest assistant response and appends them to the
# queue file. Scan model is read from voca-config.json (key: scan.model).
#
# Recursion guard: VOCA_HOOK_RUNNING=1 is exported so the nested claude
# session's Stop hook (voca-extract.sh) exits immediately.

set -uo pipefail

export VOCA_HOOK_RUNNING=1

TRANSCRIPT="${1:-}"
MODE="${2:-last}"           # "last" (default — last assistant turn) | "full" (entire transcript)

# Resolve plugin paths via lib.sh (handles CLAUDE_PLUGIN_ROOT/DATA + legacy fallback).
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_GUESS="${CLAUDE_PLUGIN_ROOT:-$(cd "$HOOK_DIR/.." && pwd)}"
. "$PLUGIN_ROOT_GUESS/scripts/lib.sh"
. "$PLUGIN_ROOT_GUESS/scripts/lib-config.sh"

QUEUE="$QUEUE_PATH"
LOG="$HOOK_LOG"
LOCK_DIR="$STATE_DIR/.voca-extract.lock.d"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Single-flight lock via mkdir (atomic, cross-platform — macOS has no flock)
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # If the lock dir is older than 60s, assume the previous run died and steal it
  if [[ -d "$LOCK_DIR" ]]; then
    AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if (( AGE > 60 )); then
      rmdir "$LOCK_DIR" 2>/dev/null || true
      mkdir "$LOCK_DIR" 2>/dev/null || { printf '[%s] cannot acquire lock\n' "$(date)" >> "$LOG"; exit 0; }
    else
      printf '[%s] another extractor running (lock age %ss), skip\n' "$(date)" "$AGE" >> "$LOG"
      exit 0
    fi
  fi
fi
trap "rmdir '$LOCK_DIR' 2>/dev/null || true" EXIT

now_ms() { python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0; }
START=$(now_ms)

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

# --- pull text from transcript (mode-dependent) ------------------------
if [[ "$MODE" == "full" ]]; then
  LAST=$(jq -s '
    [ .[] | select(.type == "assistant" or .type == "user") |
      (.type | if . == "user" then "[USER]" else "[ASSISTANT]" end) as $tag |
      ((.message.content // []) | (if type == "array" then . else [] end) |
       map(select(type == "object" and .type == "text") | .text) | join("\n")) as $txt |
      "\($tag)\n\($txt)" ] | join("\n\n")
  ' "$TRANSCRIPT" 2>/dev/null | jq -r . 2>/dev/null || echo "")
  MAX_CHARS=30000
  MAX_CANDS=10
else
  LAST=$(jq -s '
    map(select(.type == "assistant")) |
    if length == 0 then "" else
      last | (.message.content // []) | map(select(.type == "text") | .text) | join("\n")
    end
  ' "$TRANSCRIPT" 2>/dev/null | jq -r . 2>/dev/null || echo "")
  MAX_CHARS=4000
  MAX_CANDS=3
fi

if [[ -z "$LAST" || ${#LAST} -lt 80 ]]; then
  exit 0
fi

TRUNCATED=$(printf '%s' "$LAST" | head -c "$MAX_CHARS")

# --- prompt Haiku ------------------------------------------------------
# Resolve the user's primary language (controls the language of `hint` and the
# "speaker" framing). Fallback to Korean preserves legacy behavior when the
# profile is missing or the helper script is unavailable.
PRIMARY_CODE=$(bash "$PLUGIN_ROOT_GUESS/scripts/lib-profile.sh" primary_lang 2>/dev/null || echo "ko")
case "$PRIMARY_CODE" in
  en) PRIMARY_NAME="English" ;;
  ja) PRIMARY_NAME="Japanese" ;;
  *)  PRIMARY_NAME="Korean" ;;
esac

TRACKED_CONTEXT=""
if [[ -f "$WORDS_TSV" ]]; then
  TRACKED_WORDS=$(awk -F'\t' 'NR>1 && $1!="" {print $1}' "$WORDS_TSV" | head -200 | paste -sd', ' -)
  if [[ -n "$TRACKED_WORDS" ]]; then
    TRACKED_CONTEXT="- Equivalent forms (translations, transliterations, loanwords) of already-tracked words: ${TRACKED_WORDS}"
  fi
fi

LEVEL_CONTEXT=""
if [[ -f "$PROFILE_PATH" ]]; then
  LEVEL_CONTEXT=$(jq -r '
    [.languages // {} | to_entries[]
     | select(.value.estimated_size != null and .value.estimated_size > 0)
     | "\(.key | ascii_upcase): ~\(.value.estimated_size) words (\(.value.level_band // "unknown"))"]
    | if length > 0 then
        "Tested vocabulary levels:\\n" + join("\\n")
      else "" end
  ' "$PROFILE_PATH" 2>/dev/null || echo "")
fi

PROMPT=$(cat <<'EOF'
You extract candidate vocabulary words a {{PRIMARY}} speaker likely does not know from the text below.
{{LEVEL_CONTEXT}}
Pick at most {{MAX_CANDS}} words. Skip:
- Common {{PRIMARY}} words
- Brand / product / company names
- Trivially-known English (the, system, code, file, user, server, client)
- Words clearly below the user's demonstrated level in ANY language
- Words that appear after [USER] tags — the user typed them and already knows them
{{TRACKED_CONTEXT}}

Prefer:
- Specialized jargon (technical, medical, financial, legal, scientific)
- Foreign loanwords or non-{{PRIMARY}} words central to the meaning
- Technical acronyms (e.g. "MTU", "IRQ")

Output ONLY raw JSON — no markdown fences, no prose, no commentary:
{"candidates":[{"word":"...","lang":"en|ja|other","hint":"<one line in {{PRIMARY}}>"}]}

If nothing notable, output exactly: {"candidates":[]}

TEXT:
EOF
)
PROMPT=${PROMPT//\{\{MAX_CANDS\}\}/$MAX_CANDS}
PROMPT=${PROMPT//\{\{PRIMARY\}\}/$PRIMARY_NAME}
PROMPT=${PROMPT//\{\{LEVEL_CONTEXT\}\}/$LEVEL_CONTEXT}
PROMPT=${PROMPT//\{\{TRACKED_CONTEXT\}\}/$TRACKED_CONTEXT}
PROMPT="${PROMPT}
${TRUNCATED}"

# Resolve scan model from config (default haiku). Allowed: haiku|sonnet|opus.
# Unknown values fall back to haiku to keep cost predictable.
SCAN_MODEL=$(config_get scan.model haiku)
case "$SCAN_MODEL" in
  haiku|sonnet|opus) ;;
  *) SCAN_MODEL=haiku ;;
esac

OUT=$(claude -p --model "$SCAN_MODEL" "$PROMPT" 2>>"$LOG") || { printf '[%s] claude -p failed (model=%s)\n' "$(date)" "$SCAN_MODEL" >> "$LOG"; exit 0; }

# Strip markdown code fences if present (avoid backticks in $() — bash treats
# them as nested command substitution even inside single quotes)
FENCE=$(printf '\140\140\140')
CLEAN=$(printf '%s' "$OUT" | grep -v -F "$FENCE" || true)

CANDIDATES=$(printf '%s' "$CLEAN" | jq -c '.candidates // []' 2>/dev/null || echo "[]")

if [[ -z "$CANDIDATES" || "$CANDIDATES" == "[]" ]]; then
  printf '[%s] no candidates\n' "$(date)" >> "$LOG"
  exit 0
fi

# --- dedup against voca.tsv + log "already known" rows ------------------
# Skip any word already tracked in voca.tsv (regardless of status), OR
# previously rejected via the picker with reason="user marked as already known
# via picker". Without the log-based filter, words the user explicitly said
# they already know would keep re-surfacing every scan.
# WORDS_TSV / LOG_TSV come from lib.sh (already sourced above)
SKIP_LIST=$(
  { [[ -f "$WORDS_TSV" ]] && awk -F'\t' 'NR>1 && $1!="" {print tolower($1)}' "$WORDS_TSV";
    [[ -f "$LOG_TSV" ]] && awk -F'\t' 'NR>1 && $1!="" && $4=="user marked as already known via picker" {print tolower($1)}' "$LOG_TSV";
  } | sort -u
)
if [[ -n "$SKIP_LIST" ]]; then
  BEFORE=$(printf '%s' "$CANDIDATES" | jq 'length')
  CANDIDATES=$(printf '%s' "$CANDIDATES" | jq --arg s "$SKIP_LIST" '
    ($s | split("\n") | map(select(length > 0))) as $skip |
    [ .[] | select((.word | ascii_downcase) as $w | ($skip | index($w)) | not) ]
  ' 2>/dev/null || printf '%s' "$CANDIDATES")
  AFTER=$(printf '%s' "$CANDIDATES" | jq 'length')
  if [[ "$BEFORE" != "$AFTER" ]]; then
    printf '[%s] dedup filtered %s -> %s\n' "$(date)" "$BEFORE" "$AFTER" >> "$LOG"
  fi
  if [[ "$AFTER" == "0" ]]; then
    exit 0
  fi
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
END=$(now_ms)
LAT=$(( END - START ))

ENRICHED=$(printf '%s' "$CANDIDATES" | jq --arg ts "$NOW" --argjson ms "$LAT" '
  map(. + {extracted_at: $ts, hook_latency_ms: $ms, shown: false, logged: false})
') || exit 0

if [[ ! -f "$QUEUE" ]]; then
  echo '{"pending":[]}' > "$QUEUE"
fi

TMP=$(mktemp)
jq --argjson new "$ENRICHED" '
  .pending = ((.pending // []) + $new) | .pending |= (.[-50:])
' "$QUEUE" > "$TMP" 2>/dev/null && mv "$TMP" "$QUEUE" || rm -f "$TMP"

COUNT=$(printf '%s' "$ENRICHED" | jq 'length')
printf '[%s] queued %s candidates (latency %sms)\n' "$(date)" "$COUNT" "$LAT" >> "$LOG"
