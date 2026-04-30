#!/usr/bin/env bash
# One-time migration: pull all rows from Notion's Vocab DB + Candidates Log
# and append them to vocab.tsv / vocab-candidates-log.tsv.
#
# Requires `notion_token` in ~/.claude/state/vocab-config.json (Internal Integration token,
# integration must be connected to both DBs in Notion).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

CONFIG="${VOCAB_CONFIG:-$CONFIG_PATH}"
if [[ ! -f "$CONFIG" ]]; then
  echo "config missing: $CONFIG" >&2; exit 2
fi

NOTION_TOKEN=$(jq -r '.notion_token // empty' "$CONFIG")
if [[ -z "$NOTION_TOKEN" || "$NOTION_TOKEN" == "null" ]]; then
  cat >&2 <<EOF
import-from-notion: notion_token missing in $CONFIG.

Set up an internal integration once:
  1) https://www.notion.so/profile/integrations -> "New internal integration"
     (name: vocab-cli, capabilities: Read content)
  2) Copy the Internal Integration Token (secret_...)
  3) Open the Vocab DB and the Vocab Candidates Log DB; ... > Connections > add vocab-cli to both
  4) jq '. + {notion_token: "secret_..."}' $CONFIG > /tmp/vc.json && mv /tmp/vc.json $CONFIG && chmod 600 $CONFIG

After import, the token can be discarded — the TSV files are self-sufficient.
EOF
  exit 2
fi

VOCAB_DB_ID=$(jq -r '.vocab_db.database_id' "$CONFIG")
LOG_DB_ID=$(jq -r '.candidates_log_db.database_id' "$CONFIG")
NOTION_API="https://api.notion.com/v1"
NOTION_VERSION="2022-06-28"

notion_query_db() {
  local db_id="$1" cursor="${2:-}"
  local body
  if [[ -n "$cursor" ]]; then
    body=$(jq -nc --arg c "$cursor" '{ start_cursor: $c, page_size: 100 }')
  else
    body='{"page_size":100}'
  fi
  curl -sS -X POST "${NOTION_API}/databases/${db_id}/query" \
    -H "Authorization: Bearer ${NOTION_TOKEN}" \
    -H "Notion-Version: ${NOTION_VERSION}" \
    -H "Content-Type: application/json" \
    -d "$body"
}

paginate_db() {
  local db_id="$1"
  local cursor=""
  local has_more="true"
  while [[ "$has_more" == "true" ]]; do
    local resp
    resp=$(notion_query_db "$db_id" "$cursor")
    local err
    err=$(echo "$resp" | jq -r '.message // empty')
    if [[ -n "$err" ]]; then
      echo "Notion error: $err" >&2
      return 1
    fi
    echo "$resp"
    has_more=$(echo "$resp" | jq -r '.has_more // false')
    cursor=$(echo "$resp" | jq -r '.next_cursor // ""')
  done
}

# --- Words ---
WORDS_NEW=$(paginate_db "$VOCAB_DB_ID" | jq -r '.results[] | [
  ((.properties.word.title[0].plain_text // "") | gsub("[\t\r\n]"; " ")),
  (.properties.lang.select.name // ""),
  ((.properties.meaning.rich_text | map(.plain_text) | join("") | gsub("[\t\r\n]"; " "))),
  ((.properties.example.rich_text | map(.plain_text) | join("") | gsub("[\t\r\n]"; " "))),
  ((.properties.context.rich_text | map(.plain_text) | join("") | gsub("[\t\r\n]"; " "))),
  (.properties.source.select.name // ""),
  ((.properties.domain.multi_select | map(.name)) | tojson),
  ((.properties.seen_count.number // 1) | tostring),
  (.properties.first_seen_at.date.start // ""),
  (.properties.last_seen_at.date.start // ""),
  (.properties.added_via.select.name // "import"),
  (.properties.user_rating.select.name // ""),
  (.properties.status.select.name // "active"),
  ((.properties.user_note.rich_text | map(.plain_text) | join("") | gsub("[\t\r\n]"; " "))),
  "",
  ""
] | @tsv') || { echo "import failed (words)" >&2; exit 1; }

LOG_NEW=$(paginate_db "$LOG_DB_ID" | jq -r '.results[] | [
  ((.properties.candidate.title[0].plain_text // "") | gsub("[\t\r\n]"; " ")),
  (.properties.extracted_at.date.start // ""),
  (if .properties.accepted.checkbox == true then "1" elif .properties.accepted.checkbox == false then "0" else "" end),
  ((.properties.rejected_reason.rich_text | map(.plain_text) | join("") | gsub("[\t\r\n]"; " "))),
  (.properties.command_used.select.name // ""),
  ((.properties.hook_latency_ms.number // 0) | tostring),
  (.properties.lang_guess.select.name // ""),
  ((.properties.session_hint.rich_text | map(.plain_text) | join("") | gsub("[\t\r\n]"; " ")))
] | @tsv') || { echo "import failed (log)" >&2; exit 1; }

# Map old user_rating values (good/false-positive/unsure) to new (memorized/learning/unsure).
# 'good' -> 'memorized'; 'false-positive' -> '' (also force status=archived); 'unsure' -> 'unsure'.
WORDS_MAPPED=$(printf '%s\n' "$WORDS_NEW" | awk -F'\t' -v OFS='\t' '
  {
    if ($12 == "good")            { $12 = "memorized" }
    else if ($12 == "false-positive") { $12 = ""; $13 = "archived" }
    if ($13 == "")                { $13 = "active" }
    print
  }
')

lock_acquire || exit 1
trap lock_release EXIT

# Append words (skip if already present by lowercase word match).
existing=$(awk -F'\t' 'NR>1 {print tolower($1)}' "$WORDS_TSV")
W_COUNT=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  w=$(printf '%s' "$line" | awk -F'\t' '{print tolower($1)}')
  if printf '%s\n' "$existing" | grep -Fxq "$w"; then continue; fi
  printf '%s\n' "$line" >> "$WORDS_TSV"
  W_COUNT=$((W_COUNT+1))
done <<< "$WORDS_MAPPED"

L_COUNT=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  printf '%s\n' "$line" >> "$LOG_TSV"
  L_COUNT=$((L_COUNT+1))
done <<< "$LOG_NEW"

echo "Imported $W_COUNT words, $L_COUNT candidate logs."
