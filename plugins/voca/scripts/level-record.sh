#!/usr/bin/env bash
# /vocab level test — record stage results, apply midpoint formula, update profile.
# stdin JSON:
#   { "lang": "en", "stage": "stage1" | "stage2" | "stage3",
#     "results": [ { "rank": 50, "known": true }, ... ] }
# stage1: persist stage1_rank + stage2_band, print band line for next round.
# stage2: persist final estimate + level_band + history append + memorized_baseline,
#         set .stage3_recommended if user saturated the Stage 1+2 pool.
# stage3: re-finalize with combined Stage 1+2+3 results — overrides stage2 fields.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-profile.sh"
. "$SCRIPT_DIR/lib-i18n.sh"

# Per-language ceiling — must mirror LANG_CEILING in wordlists/_curate.py.
ceiling_for_lang() {
  case "$1" in
    en) echo 60000 ;;
    ja) echo 50000 ;;
    ko) echo 45000 ;;
    *)  echo 50000 ;;
  esac
}

INPUT=$(cat)
if [[ -z "$INPUT" ]]; then
  echo "level-record.sh: empty stdin (expected JSON)" >&2; exit 1
fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  echo "level-record.sh: invalid JSON on stdin" >&2; exit 1
fi

LANG_ARG=$(printf '%s' "$INPUT" | jq -r '.lang // empty')
STAGE=$(printf '%s' "$INPUT" | jq -r '.stage // empty')
case "$LANG_ARG" in en|ja|ko) ;; *) echo "level-record.sh: lang must be en|ja|ko" >&2; exit 2 ;; esac
case "$STAGE" in stage1|stage2|stage3) ;; *) echo "level-record.sh: stage must be stage1|stage2|stage3" >&2; exit 2 ;; esac

LANG_HI=$(ceiling_for_lang "$LANG_ARG")

RESULTS_TSV=$(printf '%s' "$INPUT" \
  | jq -r '.results | sort_by(.rank) | .[] | "\(.rank)\t\(if .known then 1 else 0 end)"')
N=$(printf '%s\n' "$RESULTS_TSV" | sed '/^$/d' | wc -l | tr -d ' ')
if (( N == 0 )); then
  echo "level-record.sh: empty results" >&2; exit 1
fi

# Midpoint: argmin |#unknown_before - #known_after|.
RAW_RANK=$(printf '%s\n' "$RESULTS_TSV" | awk -F'\t' '
  { rank[NR]=$1+0; known[NR]=$2+0 }
  END {
    n = NR; if (n == 0) { print 0; exit }
    best_d = 1e18; best_i = 1
    for (i = 1; i <= n; i++) {
      bu = 0; for (j = 1; j < i;  j++) if (known[j] == 0) bu++
      ak = 0; for (j = i+1; j <= n; j++) if (known[j] == 1) ak++
      d = bu - ak; if (d < 0) d = -d
      if (d < best_d) { best_d = d; best_i = i }
    }
    print rank[best_i]
  }
')
# Edge cases: if everyone known → estimate ≈ max rank; if none known → ≈ min rank
ALL_KNOWN=$(printf '%s\n' "$RESULTS_TSV" | awk -F'\t' '$2==0{f=1} END{print (f?0:1)}')
NONE_KNOWN=$(printf '%s\n' "$RESULTS_TSV" | awk -F'\t' '$2==1{f=1} END{print (f?0:1)}')
KNOWN_COUNT=$(printf '%s\n' "$RESULTS_TSV" | awk -F'\t' '$2==1{c++} END{print c+0}')
MAX_RANK=$(printf '%s\n' "$RESULTS_TSV" | awk -F'\t' 'BEGIN{m=0} { if ($1+0>m) m=$1+0 } END{print m}')
MIN_RANK=$(printf '%s\n' "$RESULTS_TSV" | awk -F'\t' 'BEGIN{m=1e18} { if ($1+0<m) m=$1+0 } END{print m}')
if [[ "$ALL_KNOWN" == "1" ]]; then RAW_RANK=$MAX_RANK; fi
if [[ "$NONE_KNOWN" == "1" ]]; then RAW_RANK=$MIN_RANK; fi

ROUNDED=$(round_estimate "$RAW_RANK")
BAND=$(band_for_size "$ROUNDED" "$LANG_ARG")
PCTL=$(percentile_for_size "$ROUNDED" "$LANG_ARG")
LANG_UPPER=$(printf '%s' "$LANG_ARG" | tr '[:lower:]' '[:upper:]')
TODAY=$(today)

CURRENT_LANG=$(profile_lang "$LANG_ARG")
[[ "$CURRENT_LANG" == "null" || -z "$CURRENT_LANG" ]] && CURRENT_LANG='{}'

if [[ "$STAGE" == "stage1" ]]; then
  # narrow band [/4, x4] clamped to [50, lang ceiling]
  BMIN=$(awk -v r="$RAW_RANK" 'BEGIN{ v=int(r/4); if (v<50) v=50; print v }')
  BMAX=$(awk -v r="$RAW_RANK" -v hi="$LANG_HI" 'BEGIN{ v=int(r*4); if (v>hi) v=hi; print v }')

  NEW_LANG=$(printf '%s' "$CURRENT_LANG" \
    | jq --argjson r "$RAW_RANK" --argjson bmin "$BMIN" --argjson bmax "$BMAX" '
        .spoken = true
        | .stage1_rank = $r
        | .stage2_band = [$bmin, $bmax]
      ')
  printf '%s' "$NEW_LANG" | profile_write_lang "$LANG_ARG"

  ROUNDED_FMT=$(format_thousands "$ROUNDED")
  t stage1.result "$LANG_UPPER" "$ROUNDED_FMT" "$BMIN" "$BMAX"
  exit 0
fi

# stage2 / stage3 — finalize (stage3 overrides stage2 with broader probe set).
MEM_BASE=$(count_memorized_for_lang "$LANG_ARG")

# Stage 3 trigger: only meaningful at stage2 — set if user saturated Stage 1+2.
# Conditions: ≥90% known AND midpoint sits within 5000 of the probed max rank.
STAGE3_RECOMMENDED=false
if [[ "$STAGE" == "stage2" ]]; then
  THRESH=$(awk -v m="$MAX_RANK" 'BEGIN{ v=m-5000; if (v<50) v=50; print v }')
  PCT=$(awk -v k="$KNOWN_COUNT" -v n="$N" 'BEGIN{ if (n==0) print 0; else print (k*100)/n }')
  if awk "BEGIN{ exit !($PCT >= 90 && $RAW_RANK >= $THRESH) }"; then
    STAGE3_RECOMMENDED=true
  fi
fi

NEW_LANG=$(printf '%s' "$CURRENT_LANG" \
  | jq \
      --arg t "$TODAY" \
      --arg stage "$STAGE" \
      --argjson est "$ROUNDED" \
      --arg band "$BAND" \
      --arg pctl "$PCTL" \
      --argjson mid "$RAW_RANK" \
      --argjson tot "$N" \
      --argjson kn "$KNOWN_COUNT" \
      --argjson base "$MEM_BASE" \
      --argjson s3rec "$STAGE3_RECOMMENDED" '
        .spoken = true
        | .estimated_size = $est
        | .level_band = $band
        | .percentile_band = $pctl
        | .midpoint_rank = $mid
        | .probes_total = $tot
        | .probes_known = $kn
        | .tested_at = $t
        | .memorized_baseline = $base
        | .last_stage = $stage
        | .stage3_recommended = $s3rec
        | .history = ((.history // []) + [{
            tested_at: $t,
            stage: $stage,
            estimated_size: $est,
            probes_total: $tot,
            probes_known: $kn
          }])
      ')
printf '%s' "$NEW_LANG" | profile_write_lang "$LANG_ARG"
profile_first_run_complete >/dev/null

ROUNDED_FMT=$(format_thousands "$ROUNDED")
t level.final.estimate "$LANG_UPPER" "$ROUNDED_FMT" "$BAND" "$N" "$KNOWN_COUNT"
# Native-distribution percentile is shown only when the estimate enters the
# Native band (≥17000). Below that it's a category error to compare a
# foreign learner against native-speaker reference distributions.
if [[ -n "$PCTL" ]]; then
  t level.final.native_ref "$PCTL"
fi
if [[ "$STAGE3_RECOMMENDED" == "true" ]]; then
  t level.final.stage3_recommend "$LANG_ARG"
fi
