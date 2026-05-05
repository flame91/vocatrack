#!/usr/bin/env bash
# Prepare a /voca queue picker round in one shot:
#   setup-guard → empty/no_new check → re-dedup → take next ≤N unshown
#   candidates → mark them shown:true (persisted) → emit JSON payload.
#
# Usage: queue-prepare-round.sh [ROUND_SIZE]   (default 15)
#
# Output (single JSON object on stdout):
#   { "status": "setup_required" }
#   { "status": "empty",   "pending_total": 0 }
#   { "status": "no_new",  "pending_total": N }
#   { "status": "ok",      "pending_total": N,
#     "round": [ {"word","lang","hint"}, ... ],
#     "remaining_unshown": M }
#
# This collapses the prep work that /voca queue used to do in 3 separate
# Bash calls into one, so the picker UI follows after a single tool round-trip.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-i18n.sh"
. "$SCRIPT_DIR/lib-profile.sh"

ROUND_SIZE="${1:-15}"

if [[ "$(profile_first_run_state)" != "completed" ]]; then
  jq -n --arg m "$(ti setup.required)" '{status:"setup_required", message:$m}'
  exit 0
fi

if [[ ! -f "$QUEUE_PATH" ]]; then
  jq -n --arg m "$(ti queue.empty)" '{status:"empty", pending_total:0, message:$m}'
  exit 0
fi

bash "$SCRIPT_DIR/queue-dedup.sh" >/dev/null 2>&1 || true

PENDING_TOTAL=$(jq '.pending | length' "$QUEUE_PATH" 2>/dev/null || echo 0)
if [[ "$PENDING_TOTAL" -eq 0 ]]; then
  jq -n --arg m "$(ti queue.empty)" '{status:"empty", pending_total:0, message:$m}'
  exit 0
fi

UNSHOWN_TOTAL=$(jq '[.pending[] | select(.shown != true)] | length' "$QUEUE_PATH" 2>/dev/null || echo 0)
if [[ "$UNSHOWN_TOTAL" -eq 0 ]]; then
  jq -n --argjson t "$PENDING_TOTAL" --arg m "$(ti queue.no_new "$PENDING_TOTAL")" \
    '{status:"no_new", pending_total:$t, message:$m}'
  exit 0
fi

ROUND=$(jq --argjson n "$ROUND_SIZE" -c '
  [ .pending[] | select(.shown != true) | {word, lang, hint} ] | .[0:$n]
' "$QUEUE_PATH")

TMP=$(mktemp "${TMPDIR:-/tmp}/voca-round.XXXXXX") || exit 1
if jq --argjson round "$ROUND" '
  ($round | map(.word | ascii_downcase)) as $rl |
  .pending |= map(
    (.word | ascii_downcase) as $w |
    if ($rl | index($w)) != null then (.shown = true) else . end
  )
' "$QUEUE_PATH" > "$TMP"; then
  mv "$TMP" "$QUEUE_PATH"
else
  rm -f "$TMP"
  exit 1
fi

REMAINING=$(jq '[.pending[] | select(.shown != true)] | length' "$QUEUE_PATH" 2>/dev/null || echo 0)

jq -n \
  --argjson total "$PENDING_TOTAL" \
  --argjson round "$ROUND" \
  --argjson remaining "$REMAINING" \
  '{status:"ok", pending_total:$total, round:$round, remaining_unshown:$remaining}'
