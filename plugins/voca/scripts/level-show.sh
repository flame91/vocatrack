#!/usr/bin/env bash
# /voca level — render vocabulary level profile.
# Usage:
#   level-show.sh           # full block with header (for /voca level)
#   level-show.sh --inline  # compact block for stats.sh prepend
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-profile.sh"
. "$SCRIPT_DIR/lib-i18n.sh"

INLINE=0
if [[ "${1:-}" == "--inline" ]]; then INLINE=1; fi

if [[ ! -f "$PROFILE_PATH" ]]; then
  echo "Vocabulary level"
  printf '  '; t profile.empty
  exit 0
fi

PROFILE=$(profile_read)

# Render one row per language, ordered en, ja, ko.
render_row() {
  local lang="$1"
  local lang_upper
  lang_upper=$(printf '%s' "$lang" | tr '[:lower:]' '[:upper:]')
  local lang_obj
  lang_obj=$(printf '%s' "$PROFILE" | jq -c --arg l "$lang" '.languages[$l] // null')

  if [[ "$lang_obj" == "null" ]]; then
    printf '  %-3s  %-7s  %-26s  %s\n' "$lang_upper" "─────" "not measured" "/voca level test $lang"
    return
  fi

  local spoken estimated band tested mid_baseline pctl last_stage
  spoken=$(printf '%s' "$lang_obj" | jq -r '.spoken // false')
  estimated=$(printf '%s' "$lang_obj" | jq -r '.estimated_size // empty')
  band=$(printf '%s' "$lang_obj" | jq -r '.level_band // empty')
  tested=$(printf '%s' "$lang_obj" | jq -r '.tested_at // empty')
  mid_baseline=$(printf '%s' "$lang_obj" | jq -r '.memorized_baseline // 0')
  last_stage=$(printf '%s' "$lang_obj" | jq -r '.last_stage // empty')
  # Compute band + percentile fresh from current size — mapping may have
  # changed since the value was last persisted (CEFR threshold updates etc.).
  if [[ -n "$estimated" ]]; then
    band=$(band_for_size "$estimated" "$lang")
    pctl=$(percentile_for_size "$estimated" "$lang")
  else
    pctl=""
  fi

  if [[ "$spoken" != "true" ]]; then
    printf '  %-3s  %-7s  %-26s  %s\n' "$lang_upper" "─────" "not selected" ""
    return
  fi

  if [[ -z "$estimated" || -z "$tested" ]]; then
    printf '  %-3s  %-7s  %-26s  %s\n' "$lang_upper" "─────" "not measured" "/voca level test $lang"
    return
  fi

  local size_fmt mem_now mem_delta days extra
  size_fmt=$(format_thousands "$estimated")
  mem_now=$(count_memorized_for_lang "$lang")
  mem_delta=$(( mem_now - mid_baseline ))
  (( mem_delta < 0 )) && mem_delta=0
  days=$(days_since "$tested")
  extra="(+${mem_delta} since)"
  if (( days >= 90 )); then
    extra="${extra} (stale)"
  fi

  printf '  %-3s  %-7s  %-26s  tested %s  %s\n' \
    "$lang_upper" "$size_fmt" "$band" "$tested" "$extra"
  # Percentile reference line (skipped when missing — pre-Stage 3 records).
  if [[ -n "$pctl" ]]; then
    local pct_only ref_only
    pct_only="${pctl%%|*}"
    pct_only="${pct_only% }"
    ref_only="${pctl##*|}"
    ref_only="${ref_only# }"
    printf '       %s   ' "$pct_only"
    t level.show.percentile_ref "$ref_only"
  fi
}

echo "Vocabulary level"
for lang in en ja ko; do
  render_row "$lang"
done

# Stale-recommendation hint at the bottom (skip in inline mode).
if (( INLINE == 0 )); then
  STALE_LANGS=$(printf '%s' "$PROFILE" | jq -r --arg today "$(today)" '
    .languages | to_entries[] | select(.value.spoken == true and .value.tested_at != null)
    | .key as $k | .value.tested_at as $t
    | $k
  ' 2>/dev/null)
  HINTS=""
  while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    t=$(printf '%s' "$PROFILE" | jq -r --arg l "$l" '.languages[$l].tested_at // empty')
    [[ -z "$t" ]] && continue
    d=$(days_since "$t")
    if (( d >= 90 )); then
      HINTS="${HINTS}  $(t level.show.stale_hint "$l" "$d" "$l")\n"
    fi
  done <<< "$STALE_LANGS"
  if [[ -n "$HINTS" ]]; then
    echo
    printf '%b' "$HINTS"
  fi
fi
