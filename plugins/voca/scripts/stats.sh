#!/usr/bin/env bash
# /voca stats — at-a-glance dashboard.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-i18n.sh"

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
TOTAL=$(awk -F'\t' $AWK_COL_VARS    'NR>1 && $C_WORD!=""' "$WORDS_TSV" | wc -l | tr -d ' ')
ACTIVE=$(awk -F'\t' $AWK_COL_VARS   'NR>1 && $C_WORD!="" && ($C_STATUS=="active" || $C_STATUS=="")' "$WORDS_TSV" | wc -l | tr -d ' ')
MASTERED=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_STATUS=="mastered"' "$WORDS_TSV" | wc -l | tr -d ' ')
ARCHIVED=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_STATUS=="archived"' "$WORDS_TSV" | wc -l | tr -d ' ')

# --- 2. Rating -------------------------------------------------------------
MEMORIZED=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_RATING=="memorized"' "$WORDS_TSV" | wc -l | tr -d ' ')
LEARNING=$(awk  -F'\t' $AWK_COL_VARS 'NR>1 && $C_RATING=="learning"'  "$WORDS_TSV" | wc -l | tr -d ' ')
UNSURE=$(awk    -F'\t' $AWK_COL_VARS 'NR>1 && $C_RATING=="unsure"'    "$WORDS_TSV" | wc -l | tr -d ' ')
UNRATED=$(awk   -F'\t' $AWK_COL_VARS 'NR>1 && $C_WORD!="" && $C_RATING==""' "$WORDS_TSV" | wc -l | tr -d ' ')

# --- 3. Daily activity (last 7 days) --------------------------------------
DATES=()
for i in 6 5 4 3 2 1 0; do DATES+=("$(date_offset $i)"); done
ADDED_COUNTS=();   MASTERED_COUNTS=();   ARCHIVED_COUNTS=()
for d in "${DATES[@]}"; do
  ADDED_COUNTS+=($(awk    -F'\t' $AWK_COL_VARS -v d="$d" 'NR>1 && $C_FIRST_SEEN==d'  "$WORDS_TSV" | wc -l | tr -d ' '))
  MASTERED_COUNTS+=($(awk -F'\t' $AWK_COL_VARS -v d="$d" 'NR>1 && $C_MASTERED_AT==d' "$WORDS_TSV" | wc -l | tr -d ' '))
  ARCHIVED_COUNTS+=($(awk -F'\t' $AWK_COL_VARS -v d="$d" 'NR>1 && $C_ARCHIVED_AT==d' "$WORDS_TSV" | wc -l | tr -d ' '))
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
# awk emits "<avg> <count>" (or empty when count==0); bash applies i18n.
TTM_RAW=$(awk -F'\t' $AWK_COL_VARS '
  function to_epoch(d,    cmd, e) {
    cmd = "date -u -j -f %Y-%m-%d \"" d "\" +%s 2>/dev/null"
    cmd | getline e; close(cmd)
    return e
  }
  NR>1 && $C_STATUS=="mastered" && $C_FIRST_SEEN!="" && $C_MASTERED_AT!="" {
    a = to_epoch($C_FIRST_SEEN); b = to_epoch($C_MASTERED_AT)
    if (a > 0 && b >= a) { total += (b - a) / 86400; count++ }
  }
  END { if (count > 0) printf "%.1f %d", total/count, count }
' "$WORDS_TSV")
if [[ -z "$TTM_RAW" ]]; then
  TTM=$(ti stats.ttm.na)
else
  TTM=$(ti stats.ttm.value "${TTM_RAW% *}" "${TTM_RAW##* }")
fi

# --- 7. Top domains / sources / lang ---------------------------------------
NONE_LBL=$(ti stats.none)

TOP_DOMAINS=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_DOMAIN!="" && $C_DOMAIN!="[]" { print $C_DOMAIN }' "$WORDS_TSV" \
  | jq -r '.[]?' 2>/dev/null \
  | sort | uniq -c | sort -rn | head -5 \
  | awk '{ printf "  %-12s %d\n", $2, $1 }')
[[ -z "$TOP_DOMAINS" ]] && TOP_DOMAINS="$NONE_LBL"

TOP_SOURCES=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_SOURCE!="" { print $C_SOURCE }' "$WORDS_TSV" \
  | sort | uniq -c | sort -rn | head -5 \
  | awk '{ printf "  %-12s %d\n", $2, $1 }')
[[ -z "$TOP_SOURCES" ]] && TOP_SOURCES="$NONE_LBL"

LANG_DIST=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_LANG!="" { print $C_LANG }' "$WORDS_TSV" \
  | sort | uniq -c | sort -rn \
  | awk '{ printf "  %-6s %d\n", $2, $1 }')
[[ -z "$LANG_DIST" ]] && LANG_DIST="$NONE_LBL"

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
VIA_AUTO=$(awk -F'\t' $AWK_COL_VARS   'NR>1 && $C_VIA=="auto-hook"' "$WORDS_TSV" | wc -l | tr -d ' ')
VIA_MANUAL=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_VIA=="manual"'    "$WORDS_TSV" | wc -l | tr -d ' ')
VIA_REVIEW=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_VIA=="review"'    "$WORDS_TSV" | wc -l | tr -d ' ')
VIA_IMPORT=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_VIA=="import"'    "$WORDS_TSV" | wc -l | tr -d ' ')

# --- 10. command distribution (last 14d) -----------------------------------
COMMANDS_DIST=$(awk -F'\t' -v c="$CUTOFF" 'NR>1 && substr($2,1,10) >= c && $5!="" {print $5}' "$LOG_TSV" \
  | sort | uniq -c | sort -rn | head -5 \
  | awk '{ printf "%s %d", $2, $1; if (NR < 5) printf " · " }')
[[ -z "$COMMANDS_DIST" ]] && COMMANDS_DIST="$(ti stats.none)"

# --- 11. top rejected reasons ----------------------------------------------
REJECT_REASONS=$(awk -F'\t' -v c="$CUTOFF" 'NR>1 && substr($2,1,10) >= c && $4!="" {print $4}' "$LOG_TSV" \
  | sort | uniq -c | sort -rn | head -3 \
  | awk '{ reason = $2; for (i=3; i<=NF; i++) reason = reason " " $i; printf "    %s — %d\n", reason, $1 }')
[[ -z "$REJECT_REASONS" ]] && REJECT_REASONS="    $(ti stats.none)"

# --- 12. top by seen_count -------------------------------------------------
TOP_SEEN=$(awk -F'\t' $AWK_COL_VARS 'NR>1 && $C_WORD!=""' "$WORDS_TSV" | sort -t$'\t' -k${C_SEEN},${C_SEEN}nr | head -5 \
  | awk -F'\t' $AWK_COL_VARS '{ printf "  %-15s %d×\n", $C_WORD, $C_SEEN }')
[[ -z "$TOP_SEEN" ]] && TOP_SEEN="$NONE_LBL"

# --- 13. stale active (>14d since last_seen_at) ----------------------------
LAST_SEEN_LBL=$(ti stats.stale.last_seen)
STALE=$(awk -F'\t' $AWK_COL_VARS -v c="$CUTOFF" 'NR>1 && ($C_STATUS=="active" || $C_STATUS=="") && $C_LAST_SEEN!="" && $C_LAST_SEEN < c { print $C_WORD "\t" $C_LAST_SEEN }' "$WORDS_TSV" \
  | sort -t$'\t' -k2 | head -5 \
  | awk -F'\t' -v lbl="$LAST_SEEN_LBL" '{ printf "  %-15s %s %s\n", $1, lbl, $2 }')
[[ -z "$STALE" ]] && STALE="$(ti stats.stale.none)"

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

HDR_LIFECYCLE=$(ti stats.lifecycle)
HDR_RATING=$(ti stats.rating)
TOTAL_LBL_ADDED=$(ti stats.daily.total "$ADDED_SUM")
TOTAL_LBL_MASTERED=$(ti stats.daily.total "$MASTERED_SUM")
TOTAL_LBL_ARCHIVED=$(ti stats.daily.total "$ARCHIVED_SUM")

t stats.header "$TODAY"
t stats.summary "$TOTAL" "$EXTRACTED" "$PENDING"
echo
printf '%s                %s\n' "$HDR_LIFECYCLE" "$HDR_RATING"
printf '  active    %s              memorized %s\n' "$ACTIVE" "$MEMORIZED"
printf '  mastered  %s              learning  %s\n' "$MASTERED" "$LEARNING"
printf '  archived  %s              unsure    %s\n' "$ARCHIVED" "$UNSURE"
printf '                           unrated   %s\n' "$UNRATED"
echo
t stats.daily "${DATES[0]}" "${DATES[6]}"
printf '  added     %s   %s   (%s)\n'    "$(sparkline "${ADDED_COUNTS[@]}")"    "$TOTAL_LBL_ADDED"    "${ADDED_COUNTS[*]}"
printf '  mastered  %s   %s   (%s)\n'    "$(sparkline "${MASTERED_COUNTS[@]}")" "$TOTAL_LBL_MASTERED" "${MASTERED_COUNTS[*]}"
printf '  archived  %s   %s   (%s)\n'    "$(sparkline "${ARCHIVED_COUNTS[@]}")" "$TOTAL_LBL_ARCHIVED" "${ARCHIVED_COUNTS[*]}"
echo
t stats.velocity "$ADD_AVG" "$MAS_AVG"
t stats.streaks  "$ADDED_STREAK" "$MASTERED_STREAK"
t stats.ttm "$TTM"
echo
t stats.top_domains
printf '%s\n' "$TOP_DOMAINS"
t stats.top_sources
printf '%s\n' "$TOP_SOURCES"
t stats.lang
printf '%s\n' "$LANG_DIST"
echo
t stats.hook
t stats.hook.precision "$PRECISION" "$EXTRACTED" "$ACCEPTED" "$REJECTED" "$PENDING"
t stats.hook.latency   "$LAT_P50" "$LAT_P95"
t stats.hook.via       "$VIA_AUTO" "$VIA_MANUAL" "$VIA_REVIEW" "$VIA_IMPORT"
t stats.hook.commands  "$COMMANDS_DIST"
t stats.hook.reject_reasons
printf '%s\n' "$REJECT_REASONS"
echo
t stats.top_seen
printf '%s\n' "$TOP_SEEN"
t stats.stale
printf '%s\n' "$STALE"
