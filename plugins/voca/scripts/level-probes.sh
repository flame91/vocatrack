#!/usr/bin/env bash
# /voca level test — sample probe words for a stage.
# Usage:
#   level-probes.sh --lang en --stage stage1
#   level-probes.sh --lang en --stage stage2 --band-min 2000 --band-max 32000
#   level-probes.sh --lang ko --stage stage3 --exclude-words "<csv of stage1+2 words>"
# Output (stdout): JSON
#   {"lang":"en","stage":"stage1","probes":[{"rank":50,"word":"right"}, ...]}
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# Per-language ceilings — must mirror LANG_CEILING in wordlists/_curate.py.
ceiling_for_lang() {
  case "$1" in
    en) echo 60000 ;;
    ja) echo 50000 ;;
    ko) echo 45000 ;;
    *)  echo 50000 ;;
  esac
}

LANG_ARG=""
STAGE=""
BAND_MIN=""
BAND_MAX=""
EXCLUDE_WORDS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang)          LANG_ARG="${2:-}"; shift 2 ;;
    --stage)         STAGE="${2:-}"; shift 2 ;;
    --band-min)      BAND_MIN="${2:-}"; shift 2 ;;
    --band-max)      BAND_MAX="${2:-}"; shift 2 ;;
    --exclude-words) EXCLUDE_WORDS="${2:-}"; shift 2 ;;
    *) echo "level-probes.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$LANG_ARG" in en|ja|ko) ;; *) echo "level-probes.sh: --lang must be en|ja|ko (got: $LANG_ARG)" >&2; exit 2 ;; esac
case "$STAGE" in stage1|stage2|stage3) ;; *) echo "level-probes.sh: --stage must be stage1|stage2|stage3 (got: $STAGE)" >&2; exit 2 ;; esac

LANG_HI=$(ceiling_for_lang "$LANG_ARG")

# Stage 3 reads the rare-word file (currently ko-only).
if [[ "$STAGE" == "stage3" ]]; then
  WORDLIST="$SCRIPT_DIR/wordlists/${LANG_ARG}.rare.tsv"
else
  WORDLIST="$SCRIPT_DIR/wordlists/${LANG_ARG}.probes.tsv"
fi
[[ -f "$WORDLIST" ]] || { echo "level-probes.sh: wordlist not found: $WORDLIST" >&2; exit 1; }

# Stage parameters
if [[ "$STAGE" == "stage1" ]]; then
  TARGET_N=32
  LO=50
  HI="$LANG_HI"
elif [[ "$STAGE" == "stage2" ]]; then
  TARGET_N=64
  LO="${BAND_MIN:-}"
  HI="${BAND_MAX:-}"
  if [[ -z "$LO" || -z "$HI" ]]; then
    echo "level-probes.sh: stage2 requires --band-min and --band-max" >&2; exit 2
  fi
else
  # stage3 — log-spaced over the entire rare-word range [20000, ceiling].
  # Mirrors RARE_RANK_LO in wordlists/_curate.py.
  TARGET_N=32
  LO=20000
  HI="$LANG_HI"
fi

# Build exclusion list (written to a temp file so awk can ingest it without
# choking on newlines inside -v values):
#   1. words user already mastered/memorized in voca.tsv (lang-scoped)
#   2. words passed via --exclude-words (comma-separated; used to dedup
#      Stage 2 against Stage 1 picks within the same test session).
EXCL_FILE=$(mktemp "${TMPDIR:-/tmp}/voca-excl.XXXXXX") || exit 1
trap 'rm -f "$EXCL_FILE"' EXIT
awk -F'\t' -v l="$LANG_ARG" '
  NR>1 && $1!="" && $2==l && ($13=="mastered" || $12=="memorized") {
    print tolower($1)
  }
' "$WORDS_TSV" 2>/dev/null > "$EXCL_FILE"
if [[ -n "$EXCLUDE_WORDS" ]]; then
  printf '%s' "$EXCLUDE_WORDS" | tr ',' '\n' | awk 'NF { print tolower($0) }' >> "$EXCL_FILE"
fi

# Read pool: skip comment lines + header, keep (rank, word).
# Filter by [LO, HI] band and remove exclusions.
POOL=$(awk -F'\t' -v lo="$LO" -v hi="$HI" -v excl_file="$EXCL_FILE" '
  BEGIN {
    while ((getline line < excl_file) > 0) {
      if (line != "") ex[line] = 1
    }
    close(excl_file)
  }
  /^#/         { next }
  /^rank\t/    { next }
  $1 == ""     { next }
  {
    r = $1 + 0
    w = $2
    if (r < lo || r > hi) next
    lw = tolower(w)
    if (lw in ex) next
    print r "\t" w
  }
' "$WORDLIST")

POOL_N=$(printf '%s\n' "$POOL" | sed '/^$/d' | wc -l | tr -d ' ')
if (( POOL_N == 0 )); then
  echo "level-probes.sh: pool empty for lang=$LANG_ARG band=[$LO,$HI]" >&2
  exit 1
fi

# Cap target N to pool size.
N=$TARGET_N
if (( N > POOL_N )); then N=$POOL_N; fi

# Pick N log-spaced probes from POOL by nearest-rank match.
# Compute log-spaced targets: t_k = LO * (HI/LO)^(k/(N-1)), then for each target take
# the pool entry with the smallest |log(rank) - log(target)| not already chosen.
PICKED=$(printf '%s\n' "$POOL" | sed '/^$/d' | awk -F'\t' -v lo="$LO" -v hi="$HI" -v n="$N" '
  {
    rank[NR] = $1 + 0
    word[NR] = $2
    total = NR
  }
  END {
    if (n <= 0 || total == 0) exit
    if (n == 1) {
      # midpoint of band
      tgt = sqrt(lo * hi)
      best = 1; best_d = 1e99
      for (i = 1; i <= total; i++) {
        d = log(rank[i]) - log(tgt); if (d < 0) d = -d
        if (d < best_d) { best_d = d; best = i }
      }
      print rank[best] "\t" word[best]
      exit
    }
    log_lo = log(lo); log_hi = log(hi)
    for (k = 0; k < n; k++) {
      t = exp(log_lo + (log_hi - log_lo) * k / (n - 1))
      best = 0; best_d = 1e99
      for (i = 1; i <= total; i++) {
        if (used[i]) continue
        d = log(rank[i]) - log(t); if (d < 0) d = -d
        if (d < best_d) { best_d = d; best = i }
      }
      if (best == 0) continue
      used[best] = 1
      print rank[best] "\t" word[best]
    }
  }
' | sort -t$'\t' -k1,1n)

# Render to JSON via jq.
printf '%s\n' "$PICKED" \
  | awk -F'\t' 'BEGIN { print "[" } NR>1 { print "," } { printf "{\"rank\":%d,\"word\":%s}", $1, "\"" $2 "\"" } END { print "]" }' \
  | jq --arg lang "$LANG_ARG" --arg stage "$STAGE" '{lang: $lang, stage: $stage, probes: .}'
