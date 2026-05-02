#!/usr/bin/env bash
# /voca stats — at-a-glance dashboard.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

TODAY=$(date -u +%Y-%m-%d)

# --- helpers ---------------------------------------------------------------

# UTF-8 sparkline (8 levels). Args: integers.
sparkline() {
  local -a chars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
  local max=0 v
  for v in "$@"; do (( v > max )) && max=$v; done
  local out=""
  for v in "$@"; do
    local idx=0
    if (( max > 0 )); then idx=$(( v * 7 / max )); fi
    out="${out}${chars[$idx]}"
  done
  printf '%s' "$out"
}

sum() { local s=0; for v in "$@"; do s=$((s+v)); done; printf '%d' "$s"; }

# date -v offset works on BSD date (macOS).
date_offset() {
  date -u -j -v-${1}d +%Y-%m-%d 2>/dev/null || date -u -d "$1 days ago" +%Y-%m-%d
}

# --- 1. Lifecycle ----------------------------------------------------------
TOTAL=$(awk -F'\t'    'NR>1 && $1!=""' "$WORDS_TSV" | wc -l | tr -d ' ')
ACTIVE=$(awk -F'\t'   'NR>1 && $1!="" && ($13=="active" || $13=="")' "$WORDS_TSV" | wc -l | tr -d ' ')
MASTERED=$(awk -F'\t' 'NR>1 && $13=="mastered"' "$WORDS_TSV" | wc -l | tr -d ' ')
ARCHIVED=$(awk -F'\t' 'NR>1 && $13=="archived"' "$WORDS_TSV" | wc -l | tr -d ' ')

# --- 2. Rating -------------------------------------------------------------
MEMORIZED=$(awk -F'\t' 'NR>1 && $12=="memorized"' "$WORDS_TSV" | wc -l | tr -d ' ')
LEARNING=$(awk  -F'\t' 'NR>1 && $12=="learning"'  "$WORDS_TSV" | wc -l | tr -d ' ')
UNSURE=$(awk    -F'\t' 'NR>1 && $12=="unsure"'    "$WORDS_TSV" | wc -l | tr -d ' ')
UNRATED=$(awk   -F'\t' 'NR>1 && $1!="" && $12==""' "$WORDS_TSV" | wc -l | tr -d ' ')

# --- 3. Daily activity (last 7 days) --------------------------------------
DATES=()
for i in 6 5 4 3 2 1 0; do DATES+=("$(date_offset $i)"); done
ADDED_COUNTS=();   MASTERED_COUNTS=();   ARCHIVED_COUNTS=()
for d in "${DATES[@]}"; do
  ADDED_COUNTS+=($(awk    -F'\t' -v d="$d" 'NR>1 && $9==d'  "$WORDS_TSV" | wc -l | tr -d ' '))
  MASTERED_COUNTS+=($(awk -F'\t' -v d="$d" 'NR>1 && $15==d' "$WORDS_TSV" | wc -l | tr -d ' '))
  ARCHIVED_COUNTS+=($(awk -F'\t' -v d="$d" 'NR>1 && $16==d' "$WORDS_TSV" | wc -l | tr -d ' '))
done
ADDED_SUM=$(sum "${ADDED_COUNTS[@]}")
MASTERED_SUM=$(sum "${MASTERED_COUNTS[@]}")
ARCHIVED_SUM=$(sum "${ARCHIVED_COUNTS[@]}")

# --- 4. Velocity (7-day average) -------------------------------------------
ADD_AVG=$(awk -v s="$ADDED_SUM"    'BEGIN{ printf "%.1f", s/7 }')
MAS_AVG=$(awk -v s="$MASTERED_SUM" 'BEGIN{ printf "%.1f", s/7 }')

# --- 5. Streaks (consecutive days from today backwards) -------------------
ADDED_STREAK=0
for ((i = ${#ADDED_COUNTS[@]} - 1; i >= 0; i--)); do
  if (( ${ADDED_COUNTS[i]} > 0 )); then ADDED_STREAK=$((ADDED_STREAK+1)); else break; fi
done
MASTERED_STREAK=0
for ((i = ${#MASTERED_COUNTS[@]} - 1; i >= 0; i--)); do
  if (( ${MASTERED_COUNTS[i]} > 0 )); then MASTERED_STREAK=$((MASTERED_STREAK+1)); else break; fi
done

# --- 6. Time-to-master (avg days from first_seen_at -> mastered_at) ------
TTM=$(awk -F'\t' '
  function to_epoch(d,    cmd, e) {
    cmd = "date -u -j -f %Y-%m-%d \"" d "\" +%s 2>/dev/null"
    cmd | getline e; close(cmd)
    return e
  }
  NR>1 && $13=="mastered" && $9!="" && $15!="" {
    a = to_epoch($9); b = to_epoch($15)
    if (a > 0 && b >= a) { total += (b - a) / 86400; count++ }
  }
  END {
    if (count > 0) printf "%.1f days (n=%d)", total/count, count
    else printf "n/a"
  }
' "$WORDS_TSV")

# --- 7. Top domains / sources / lang ---------------------------------------
TOP_DOMAINS=$(awk -F'\t' 'NR>1 && $7!="" && $7!="[]" { print $7 }' "$WORDS_TSV" \
  | jq -r '.[]?' 2>/dev/null \
  | sort | uniq -c | sort -rn | head -5 \
  | awk '{ printf "  %-12s %d\n", $2, $1 }')
[[ -z "$TOP_DOMAINS" ]] && TOP_DOMAINS="  (none)"

TOP_SOURCES=$(awk -F'\t' 'NR>1 && $6!="" { print $6 }' "$WORDS_TSV" \
  | sort | uniq -c | sort -rn | head -5 \
  | awk '{ printf "  %-12s %d\n", $2, $1 }')
[[ -z "$TOP_SOURCES" ]] && TOP_SOURCES="  (none)"

LANG_DIST=$(awk -F'\t' 'NR>1 && $2!="" { print $2 }' "$WORDS_TSV" \
  | sort | uniq -c | sort -rn \
  | awk '{ printf "  %-6s %d\n", $2, $1 }')
[[ -z "$LANG_DIST" ]] && LANG_DIST="  (none)"

# --- 8. Hook (last 14d) ----------------------------------------------------
CUTOFF=$(date_offset 14)
EXTRACTED=$(awk -F'\t' -v c="$CUTOFF" 'NR>1 && substr($2,1,10) >= c' "$LOG_TSV" | wc -l | tr -d ' ')
ACCEPTED=$(awk  -F'\t' -v c="$CUTOFF" 'NR>1 && substr($2,1,10) >= c && $3=="1"' "$LOG_TSV" | wc -l | tr -d ' ')
REJECTED=$(awk  -F'\t' -v c="$CUTOFF" 'NR>1 && substr($2,1,10) >= c && $3=="0"' "$LOG_TSV" | wc -l | tr -d ' ')
PENDING=$(jq '.pending | length' "$QUEUE_PATH" 2>/dev/null || echo 0)
PRECISION="-"
PROCESSED=$((ACCEPTED + REJECTED))
if (( PROCESSED > 0 )); then
  PRECISION=$(awk -v a="$ACCEPTED" -v p="$PROCESSED" 'BEGIN{printf "%d%%", a*100/p}')
fi

# Latency p50 / p95
LATENCIES=$(awk -F'\t' -v c="$CUTOFF" 'NR>1 && substr($2,1,10) >= c && $6!="" && $6+0>0 {print $6}' "$LOG_TSV" | sort -n)
LAT_COUNT=0
[[ -n "$LATENCIES" ]] && LAT_COUNT=$(printf '%s\n' "$LATENCIES" | wc -l | tr -d ' ')
LAT_P50="-"; LAT_P95="-"
if (( LAT_COUNT > 0 )); then
  P50=$(( (LAT_COUNT + 1) / 2 ))
  P95=$(( LAT_COUNT * 95 / 100 )); (( P95 < 1 )) && P95=1
  V50=$(printf '%s\n' "$LATENCIES" | sed -n "${P50}p")
  V95=$(printf '%s\n' "$LATENCIES" | sed -n "${P95}p")
  LAT_P50=$(awk -v v="$V50" 'BEGIN{printf "%.1fs", v/1000}')
  LAT_P95=$(awk -v v="$V95" 'BEGIN{printf "%.1fs", v/1000}')
fi

# --- 9. added_via ratio ----------------------------------------------------
VIA_AUTO=$(awk -F'\t'   'NR>1 && $11=="auto-hook"' "$WORDS_TSV" | wc -l | tr -d ' ')
VIA_MANUAL=$(awk -F'\t' 'NR>1 && $11=="manual"'    "$WORDS_TSV" | wc -l | tr -d ' ')
VIA_REVIEW=$(awk -F'\t' 'NR>1 && $11=="review"'    "$WORDS_TSV" | wc -l | tr -d ' ')
VIA_IMPORT=$(awk -F'\t' 'NR>1 && $11=="import"'    "$WORDS_TSV" | wc -l | tr -d ' ')

# --- 10. command distribution (last 14d) -----------------------------------
COMMANDS_DIST=$(awk -F'\t' -v c="$CUTOFF" 'NR>1 && substr($2,1,10) >= c && $5!="" {print $5}' "$LOG_TSV" \
  | sort | uniq -c | sort -rn | head -5 \
  | awk '{ printf "%s %d", $2, $1; if (NR < 5) printf " · " }')
[[ -z "$COMMANDS_DIST" ]] && COMMANDS_DIST="(none)"

# --- 11. top rejected reasons ----------------------------------------------
REJECT_REASONS=$(awk -F'\t' -v c="$CUTOFF" 'NR>1 && substr($2,1,10) >= c && $4!="" {print $4}' "$LOG_TSV" \
  | sort | uniq -c | sort -rn | head -3 \
  | awk '{ reason = $2; for (i=3; i<=NF; i++) reason = reason " " $i; printf "    %s — %d\n", reason, $1 }')
[[ -z "$REJECT_REASONS" ]] && REJECT_REASONS="    (none)"

# --- 12. top by seen_count -------------------------------------------------
TOP_SEEN=$(awk -F'\t' 'NR>1 && $1!=""' "$WORDS_TSV" | sort -t$'\t' -k8,8nr | head -5 \
  | awk -F'\t' '{ printf "  %-15s %d×\n", $1, $8 }')
[[ -z "$TOP_SEEN" ]] && TOP_SEEN="  (none)"

# --- 13. stale active (>14d since last_seen_at) ----------------------------
STALE=$(awk -F'\t' -v c="$CUTOFF" 'NR>1 && ($13=="active" || $13=="") && $10!="" && $10 < c { print $1 "\t" $10 }' "$WORDS_TSV" \
  | sort -t$'\t' -k2 | head -5 \
  | awk -F'\t' '{ printf "  %-15s last seen %s\n", $1, $2 }')
[[ -z "$STALE" ]] && STALE="  (none — all active words seen within 14d)"

# --- print -----------------------------------------------------------------

# Two-column day labels for sparklines
DAY_LABELS=""
for d in "${DATES[@]}"; do DAY_LABELS="${DAY_LABELS}${d:5} "; done

# Vocabulary level block (from level-show.sh). Skip silently if unavailable.
LEVEL_BLOCK=""
if [[ -x "$SCRIPT_DIR/level-show.sh" ]]; then
  LEVEL_BLOCK=$(bash "$SCRIPT_DIR/level-show.sh" --inline 2>/dev/null || true)
fi
if [[ -n "$LEVEL_BLOCK" ]]; then
  printf '%s\n\n' "$LEVEL_BLOCK"
fi

cat <<EOF
═══ Voca Stats (as of ${TODAY}) ════════════════════════════════════
Total: ${TOTAL} words · ${EXTRACTED} candidates extracted (14d) · queue ${PENDING}

Lifecycle                Rating
  active    ${ACTIVE}              memorized ${MEMORIZED}
  mastered  ${MASTERED}              learning  ${LEARNING}
  archived  ${ARCHIVED}              unsure    ${UNSURE}
                           unrated   ${UNRATED}

Daily activity (last 7d, ${DATES[0]} → ${DATES[6]})
  added     $(sparkline "${ADDED_COUNTS[@]}")   total ${ADDED_SUM}   (${ADDED_COUNTS[*]})
  mastered  $(sparkline "${MASTERED_COUNTS[@]}")   total ${MASTERED_SUM}   (${MASTERED_COUNTS[*]})
  archived  $(sparkline "${ARCHIVED_COUNTS[@]}")   total ${ARCHIVED_SUM}   (${ARCHIVED_COUNTS[*]})

Velocity (7d avg): +${ADD_AVG} added/day · +${MAS_AVG} mastered/day
Streaks: added ${ADDED_STREAK}d · mastered ${MASTERED_STREAK}d
Time-to-master: ${TTM}

Top domains
${TOP_DOMAINS}
Top sources
${TOP_SOURCES}
Lang
${LANG_DIST}

Hook (last 14d)
  precision  ${PRECISION}   (extracted ${EXTRACTED}, accepted ${ACCEPTED}, rejected ${REJECTED}, pending ${PENDING})
  latency    p50 ${LAT_P50} · p95 ${LAT_P95}
  via        auto-hook ${VIA_AUTO} · manual ${VIA_MANUAL} · review ${VIA_REVIEW} · import ${VIA_IMPORT}
  commands   ${COMMANDS_DIST}
  top reject reasons
${REJECT_REASONS}

Top by seen_count
${TOP_SEEN}
Stale active (>14d)
${STALE}
EOF
