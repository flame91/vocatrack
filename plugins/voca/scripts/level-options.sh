#!/usr/bin/env bash
# /voca level test — build AskUserQuestion option blobs from probe JSON,
# verbatim. Eliminates transcription typos when the model assembles labels
# manually (e.g. Hangul codepoint confusion: 쉬 U+C26C vs 쉰 U+C270).
#
# Usage:
#   level-options.sh <probe-json-file>
#   echo "$STAGE1_JSON" | level-options.sh -
#
# Output (stdout): JSON array of "round" blobs. Each round = one
# AskUserQuestion call (≤4 questions × ≤4 options = ≤16 word slots).
#   [
#     {
#       "round": 1,
#       "questions": [
#         {
#           "question": "아는 단어를 체크하세요 (Stage 1, 1/2).",
#           "header":   "KO 테스트",
#           "multiSelect": true,
#           "options": [
#             {"label": "<word>", "description": ""},
#             ...
#           ]
#         },
#         ...
#       ]
#     },
#     ...
#   ]
#
# The caller (model) MUST pass these option blobs through to AskUserQuestion
# without re-typing labels. A self-check verifier (level-options-verify.sh)
# can confirm round-trip integrity.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-i18n.sh"

input="${1:-}"
if [[ -z "$input" || "$input" == "-" ]]; then
  payload=$(cat)
else
  payload=$(cat "$input")
fi

lang=$(printf '%s' "$payload" | jq -r '.lang')
stage=$(printf '%s' "$payload" | jq -r '.stage')
lang_upper=$(printf '%s' "$lang" | tr '[:lower:]' '[:upper:]')
header=$(ti level.test.header "$lang_upper")

# 16 word-slots per round (4 questions × 4 options).
# Stage 1 = 32 probes → 2 rounds. Stage 2 = ≤64 → ≤4 rounds. Stage 3 = 32 → 2 rounds.
slots_per_round=16
options_per_question=4

total=$(printf '%s' "$payload" | jq -r '.probes | length')
total_rounds=$(( (total + slots_per_round - 1) / slots_per_round ))

stage_label() {
  case "$1" in
    stage1) echo "Stage 1" ;;
    stage2) echo "Stage 2" ;;
    stage3) echo "Stage 3" ;;
    *)       echo "$1" ;;
  esac
}
slabel=$(stage_label "$stage")

# Resolve i18n question template (uses named placeholders for jq substitution).
q_template=$(_voca_lookup level.test.question "$VOCA_LOCALE_RESOLVED" 2>/dev/null) \
  || q_template=$(_voca_lookup level.test.question en 2>/dev/null) \
  || q_template="Check the words you know ({stage}, {round}/{total}, q{qnum})."

# Build options, verbatim, via jq. Words flow word→label without ever
# touching shell-string interpolation, so codepoints cannot drift.
printf '%s' "$payload" | jq --argjson spr "$slots_per_round" \
  --argjson opq "$options_per_question" \
  --arg header "$header" \
  --arg slabel "$slabel" \
  --arg qtmpl "$q_template" \
  --argjson total_rounds "$total_rounds" '
  . as $root
  | [ range(0; ($root.probes | length); $spr) ] as $round_starts
  | [ $round_starts | to_entries[] | . as $r
    | ($r.value) as $rstart
    | ($r.key + 1) as $rnum
    | $root.probes[$rstart:($rstart + $spr)] as $round_words
    | {
        round: $rnum,
        questions: (
          [ range(0; ($round_words | length); $opq) ] as $qs
          | [ $qs | to_entries[] | . as $q
            | ($q.value) as $qstart
            | ($q.key + 1) as $qnum
            | $round_words[$qstart:($qstart + $opq)] as $q_words
            | {
                question: ($qtmpl | gsub("\\{stage\\}"; $slabel) | gsub("\\{round\\}"; ($rnum|tostring)) | gsub("\\{total\\}"; ($total_rounds|tostring)) | gsub("\\{qnum\\}"; ($qnum|tostring))),
                header: $header,
                multiSelect: true,
                options: [ $q_words[] | {label: .word, description: ""} ]
              }
          ]
        )
      }
  ]'
