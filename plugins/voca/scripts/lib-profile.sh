#!/usr/bin/env bash
# Helpers for ~/.claude/state/voca-profile.json (vocabulary level / language profile).
# Loaded via: . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-profile.sh"
# This file also sources lib.sh for $DB_DIR / lock_acquire / lock_release / today.
set -uo pipefail

LIB_PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$LIB_PROFILE_DIR/lib.sh"

PROFILE_LOCK_DIR="$DB_DIR/.voca-profile.lock.d"

# ---------------------------------------------------------------------------
# locking (separate from words tsv lock so they don't contend)
profile_lock_acquire() {
  local i=0
  while ! mkdir "$PROFILE_LOCK_DIR" 2>/dev/null; do
    if [[ -d "$PROFILE_LOCK_DIR" ]]; then
      local age
      age=$(( $(date +%s) - $(stat -f %m "$PROFILE_LOCK_DIR" 2>/dev/null || echo 0) ))
      (( age > 30 )) && { rmdir "$PROFILE_LOCK_DIR" 2>/dev/null || true; continue; }
    fi
    sleep 0.1
    i=$((i+1))
    (( i > 50 )) && { echo "voca-profile: lock timeout" >&2; return 1; }
  done
}
profile_lock_release() { rmdir "$PROFILE_LOCK_DIR" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Read whole profile JSON to stdout. Empty default if missing.
profile_read() {
  if [[ -f "$PROFILE_PATH" ]]; then
    cat "$PROFILE_PATH"
  else
    printf '%s\n' '{"spoken_count":0,"first_run_completed_at":null,"first_run_declined":false,"languages":{}}'
  fi
}

# Read one language object (or `null`).
profile_lang() {
  local lang="$1"
  profile_read | jq -c --arg l "$lang" '.languages[$l] // null'
}

# Atomic write of full profile from stdin.
profile_write() {
  local input
  input=$(cat)
  if ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
    echo "voca-profile: invalid JSON on stdin" >&2
    return 1
  fi
  profile_lock_acquire || return 1
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/voca-profile.XXXXXX") || { profile_lock_release; return 1; }
  printf '%s\n' "$input" > "$tmp" && mv "$tmp" "$PROFILE_PATH"
  profile_lock_release
}

# Merge a language object (stdin JSON) into profile.languages[$lang].
# Replaces the language entry entirely (caller composes the new object).
profile_write_lang() {
  local lang="$1"
  local langjson
  langjson=$(cat)
  if ! printf '%s' "$langjson" | jq -e . >/dev/null 2>&1; then
    echo "voca-profile: invalid lang JSON" >&2
    return 1
  fi
  local current
  current=$(profile_read)
  printf '%s' "$current" \
    | jq --arg l "$lang" --argjson v "$langjson" '.languages[$l] = $v' \
    | profile_write
}

# Mark first-run as declined (so voca guard stops asking).
profile_first_run_decline() {
  local current
  current=$(profile_read)
  printf '%s' "$current" \
    | jq '.first_run_declined = true' \
    | profile_write
}

# Mark first-run as completed.
profile_first_run_complete() {
  local current
  current=$(profile_read)
  printf '%s' "$current" \
    | jq --arg t "$(today)" '.first_run_completed_at = $t' \
    | profile_write
}

# Return one of: pristine | completed | declined.
profile_first_run_state() {
  if [[ ! -f "$PROFILE_PATH" ]]; then
    echo pristine
    return
  fi
  local declined completed
  declined=$(profile_read | jq -r '.first_run_declined // false')
  completed=$(profile_read | jq -r '.first_run_completed_at // empty')
  if [[ "$declined" == "true" ]]; then
    echo declined
  elif [[ -n "$completed" ]]; then
    echo completed
  else
    echo pristine
  fi
}

# Count voca.tsv rows with given lang AND user_rating=memorized.
count_memorized_for_lang() {
  local lang="$1"
  awk -F'\t' -v l="$lang" 'NR>1 && $2==l && $12=="memorized"' "$WORDS_TSV" 2>/dev/null \
    | wc -l | tr -d ' '
}

# CEFR band mapping. `band_for_size SIZE [LANG]` — LANG selects per-language
# thresholds for the native bands above C2; the A1-C2 range follows standard
# Council of Europe vocabulary thresholds and is identical across languages.
#
# Standard CEFR vocabulary thresholds (Council of Europe / practitioner consensus):
#   A1 < 1500, A2 < 2500, B1 < 5000, B2 < 8000, C1 < 12000, C2 < 17000.
# C2 is "near native" by definition — anything beyond C2 is the native range,
# which we extend per language using the available probe ceiling.
band_for_size() {
  local s="$1"
  local lang="${2:-}"
  # Shared learner-range bands (A1..C2). Per-Council of Europe.
  if   (( s < 1500 ));  then echo "A1 — Beginner";       return
  elif (( s < 2500 ));  then echo "A2 — Elementary";     return
  elif (( s < 5000 ));  then echo "B1 — Intermediate";   return
  elif (( s < 8000 ));  then echo "B2 — Upper-intermediate"; return
  elif (( s < 12000 )); then echo "C1 — Advanced";       return
  elif (( s < 17000 )); then echo "C2 — Proficient";     return
  fi
  # Native-range bands diverge per language ceiling.
  case "$lang" in
    ko) _band_ko_native "$s" ;;
    en) _band_en_native "$s" ;;
    ja) _band_ja_native "$s" ;;
    *)  echo "C2 — Proficient" ;;  # legacy: cap at C2 when lang unspecified
  esac
}

# Korean — ko probe ceiling 45000.
_band_ko_native() {
  local s="$1"
  if   (( s < 22000 )); then echo "Native — Educated adult"
  elif (( s < 30000 )); then echo "Native — Advanced"
  elif (( s < 40000 )); then echo "Native — Top tier"
  else                       echo "Native — 상위 1%"
  fi
}

# English — en probe ceiling 60000.
_band_en_native() {
  local s="$1"
  if   (( s < 25000 )); then echo "Native — Educated adult"
  elif (( s < 35000 )); then echo "Native — Advanced"
  elif (( s < 45000 )); then echo "Native — Top tier"
  elif (( s < 55000 )); then echo "Native — Heavy reader"
  else                       echo "Native — Top 1%"
  fi
}

# Japanese — ja probe ceiling 50000.
_band_ja_native() {
  local s="$1"
  if   (( s < 25000 )); then echo "Native — Educated adult"
  elif (( s < 35000 )); then echo "Native — Advanced"
  elif (( s < 45000 )); then echo "Native — Top tier"
  else                       echo "Native — 上位5%"
  fi
}

# Native-distribution percentile. `percentile_for_size SIZE LANG`.
# **Gate**: returns empty for SIZE < 17000 — below this is the CEFR learner
# range (A1-C2), where comparing against native-speaker reference distributions
# is a category error (foreign learner ≠ native speaker). Above 17000 the
# estimate is in the "Native — *" band and a native-distribution reference
# becomes meaningful.
#
# References:
#   ko: 김광해 2003 "한국어 어휘 빈도조사" + 국립국어원 2002 빈도조사 (±10%).
#   en: testyourvocab.com 2013 study (2M+ samples).
#   ja: NTT 語彙数推定テスト 補正版 (Hayashi et al.).
percentile_for_size() {
  local s="$1"
  local lang="${2:-}"
  if (( s < 17000 )); then
    echo ""
    return
  fi
  case "$lang" in
    ko) _percentile_ko "$s" ;;
    en) _percentile_en "$s" ;;
    ja) _percentile_ja "$s" ;;
    *)  echo "" ;;
  esac
}

_percentile_ko() {
  local s="$1"
  local p
  if   (( s < 22000 )); then p="평균 성인"
  elif (( s < 28000 )); then p="상위 30% (대졸 성인)"
  elif (( s < 35000 )); then p="상위 10% (어휘력 높은 성인)"
  elif (( s < 42000 )); then p="상위 3% (전문 직군 / 작가)"
  else                       p="상위 1%"
  fi
  echo "$p | 김광해 2003 / 국립국어원 빈도조사 (±10%)"
}

_percentile_en() {
  local s="$1"
  local p
  if   (( s < 25000 )); then p="Average native (adult)"
  elif (( s < 35000 )); then p="Top 30% native"
  elif (( s < 45000 )); then p="Top 10% (heavy reader)"
  elif (( s < 55000 )); then p="Top 3%"
  else                       p="Top 1%"
  fi
  echo "$p | testyourvocab.com 2013 (2M+ samples)"
}

_percentile_ja() {
  local s="$1"
  local p
  if   (( s < 25000 )); then p="中学生レベル (入門)"
  elif (( s < 35000 )); then p="中学卒 ~ 高校生"
  elif (( s < 45000 )); then p="高校卒 ~ 大学生"
  else                       p="教養人 (上位5%)"
  fi
  echo "$p | NTT 語彙数推定テスト 補正版"
}

# Round per testyourvocab convention: >10000 to nearest 100, else nearest 10.
round_estimate() {
  local s="$1"
  if (( s > 10000 )); then
    awk -v v="$s" 'BEGIN{ printf "%d\n", int((v + 50)/100)*100 }'
  else
    awk -v v="$s" 'BEGIN{ printf "%d\n", int((v + 5)/10)*10 }'
  fi
}

# Days between two ISO dates (today - tested_at). Negative => negative days.
days_since() {
  local from="$1"
  [[ -z "$from" ]] && { echo 0; return; }
  local f t
  f=$(date -u -j -f %Y-%m-%d "$from" +%s 2>/dev/null || date -u -d "$from" +%s 2>/dev/null || echo 0)
  t=$(date -u +%s)
  if [[ -z "$f" || "$f" == "0" ]]; then echo 0; return; fi
  echo $(( (t - f) / 86400 ))
}

# Format integer with thousand separators (locale-independent).
format_thousands() {
  awk -v v="$1" 'BEGIN{
    n=v+0; if (n<0){ printf "-"; n=-n }
    s=sprintf("%d", n); out=""; len=length(s)
    for (i=1; i<=len; i++) {
      out = out substr(s,i,1)
      r = len - i
      if (r>0 && r%3==0) out = out ","
    }
    print out
  }'
}

# Primary language — code (ko/en/ja). Reads .languages.{lang}.primary == true.
# Fallback "ko" when nothing is set, preserving legacy behavior.
profile_primary_lang() {
  local code
  code=$(profile_read | jq -r '
    (.languages // {}) | to_entries
    | map(select(.value.primary == true))
    | (.[0].key // "ko")
  ' 2>/dev/null)
  printf '%s' "${code:-ko}"
}

# Human-readable name for prompt interpolation.
profile_primary_lang_name() {
  case "$(profile_primary_lang)" in
    ko) printf '%s' "Korean (한국어)" ;;
    en) printf '%s' "English" ;;
    ja) printf '%s' "Japanese (日本語)" ;;
    *)  printf '%s' "Korean (한국어)" ;;
  esac
}

# CLI sub-dispatch so the file is also runnable: `bash lib-profile.sh first_run_state`.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"
  shift || true
  case "$cmd" in
    read)                  profile_read ;;
    lang)                  profile_lang "$1" ;;
    write_lang)            profile_write_lang "$1" ;;
    first_run_state)       profile_first_run_state ;;
    first_run_decline)     profile_first_run_decline ;;
    first_run_complete)    profile_first_run_complete ;;
    count_memorized)       count_memorized_for_lang "$1" ;;
    band)                  band_for_size "$1" "${2:-}" ;;
    percentile)            percentile_for_size "$1" "${2:-}" ;;
    round)                 round_estimate "$1" ;;
    days_since)            days_since "$1" ;;
    format_thousands)      format_thousands "$1" ;;
    primary_lang)          profile_primary_lang; echo ;;
    primary_lang_name)     profile_primary_lang_name; echo ;;
    *)
      echo "usage: lib-profile.sh <read|lang LANG|write_lang LANG|first_run_state|first_run_decline|first_run_complete|count_memorized LANG|band SIZE [LANG]|percentile SIZE LANG|round SIZE|days_since YYYY-MM-DD|format_thousands N|primary_lang|primary_lang_name>" >&2
      exit 2 ;;
  esac
fi
