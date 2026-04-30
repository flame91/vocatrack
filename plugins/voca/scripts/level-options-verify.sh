#!/usr/bin/env bash
# /vocab level test — verify that AskUserQuestion option labels round-trip
# match the source probe JSON byte-for-byte. Run this AFTER the model has
# constructed its AskUserQuestion payload but BEFORE actually invoking it.
#
# Usage:
#   level-options-verify.sh <probe-json-file> <auq-payload-json-file>
#   level-options-verify.sh probes.json auq.json
#
#   <probe-json>     : output of level-probes.sh — {lang, stage, probes:[{rank,word}]}
#   <auq-payload>    : the questions[] array the model is about to pass to
#                      AskUserQuestion. May be either:
#                       (a) the raw `questions` array from one round, or
#                       (b) the full `[{round, questions}, ...]` array from
#                           level-options.sh.
#
# Behavior:
#   - Extract every option label from the AUQ payload.
#   - Compare against the set of probe words.
#   - Exit 0 if every label is present in probes (no typos).
#   - Exit 1 + diff to stderr otherwise.
set -uo pipefail

probe_file="${1:?probe-json file required}"
auq_file="${2:?auq-payload file required}"

probe_words=$(jq -r '[.probes[].word] | sort | unique | .[]' "$probe_file")

# Try to detect AUQ payload shape and pull labels.
shape=$(jq -r '
  if type == "array" and (.[0] | type == "object") and (.[0] | has("round")) then "level_options"
  elif type == "array" and (.[0] | type == "object") and (.[0] | has("options")) then "questions"
  elif type == "object" and has("questions") then "single_round"
  else "unknown"
  end
' "$auq_file")

case "$shape" in
  level_options)
    auq_labels=$(jq -r '[.[].questions[].options[].label] | sort | unique | .[]' "$auq_file")
    ;;
  questions)
    auq_labels=$(jq -r '[.[].options[].label] | sort | unique | .[]' "$auq_file")
    ;;
  single_round)
    auq_labels=$(jq -r '[.questions[].options[].label] | sort | unique | .[]' "$auq_file")
    ;;
  *)
    echo "ERR: unrecognized AUQ payload shape" >&2
    exit 2
    ;;
esac

# Allow the well-known sentinel option for queue picker; level test never has it,
# so it should never fire here, but keep the filter to make the script reusable.
auq_labels=$(printf '%s\n' "$auq_labels" | grep -vxF '이 페이지의 모든 단어를 알고 있음' || true)

# Set difference: labels not in probes.
strays=$(comm -23 <(printf '%s\n' "$auq_labels") <(printf '%s\n' "$probe_words"))

if [[ -z "$strays" ]]; then
  count=$(printf '%s\n' "$auq_labels" | grep -c . || true)
  echo "OK: $count labels match probe words verbatim."
  exit 0
fi

echo "FAIL: AUQ contains label(s) not present in probe JSON. Likely transcription typo." >&2
echo "" >&2
while IFS= read -r stray; do
  [[ -z "$stray" ]] && continue
  echo "  stray label: $stray" >&2
  # Best-effort suggest closest probe word by matching first 1-2 syllables.
  prefix=$(printf '%s' "$stray" | head -c 6)  # 2 hangul syllables ≈ 6 bytes UTF-8
  match=$(printf '%s\n' "$probe_words" | grep -F "$prefix" | head -1 || true)
  [[ -n "$match" ]] && echo "    nearest probe: $match" >&2
done <<< "$strays"
exit 1
