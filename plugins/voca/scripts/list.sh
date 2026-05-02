#!/usr/bin/env bash
# /voca list [N] [--status=active|mastered|archived|all]
#
# Defaults & display columns are read from ~/.claude/state/voca-config.json
# (keys: list.default_n, list.default_status, list.sort, list.columns,
# list.widths.meaning, list.widths.domain). CLI args override config.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-config.sh"

N=$(config_get list.default_n 50)
STATUS=$(config_get list.default_status active)
SORT_SPEC=$(config_get list.sort "last_seen desc")
MEANING_W=$(config_get list.widths.meaning auto)
DOMAIN_W=$(config_get list.widths.domain auto)

COLUMNS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && COLUMNS+=("$line")
done < <(config_get_array list.columns)
if [[ ${#COLUMNS[@]} -eq 0 ]]; then
  COLUMNS=(word lang meaning source domain seen age via status rating)
fi

LANG_FILTER=$(config_get list.default_lang "")

# CLI overrides
for arg in "$@"; do
  case "$arg" in
    --status=*) STATUS="${arg#--status=}" ;;
    --lang=*)   LANG_FILTER="${arg#--lang=}" ;;
    [0-9]*)     N="$arg" ;;
  esac
done

case "$STATUS" in
  active|mastered|archived|all) ;;
  *) echo "unknown status: $STATUS (active|mastered|archived|all)" >&2; exit 1 ;;
esac

case "$LANG_FILTER" in
  ""|all|en|ja|ko|mixed|other) ;;
  *) echo "unknown lang: $LANG_FILTER (en|ja|ko|mixed|other|all)" >&2; exit 1 ;;
esac

# Adaptive width: when meaning/domain is "auto", compute from terminal width
if [[ "$MEANING_W" == "auto" || "$DOMAIN_W" == "auto" ]]; then
  if stty size &>/dev/null; then
    TERM_W=$(tput cols 2>/dev/null || echo 120)
  else
    TERM_W=140  # non-interactive (CI, Claude Code, pipe) — generous default
  fi
  FIXED=0
  HAS_MEANING=0; HAS_DOMAIN=0
  for c in "${COLUMNS[@]}"; do
    case "$c" in
      meaning) HAS_MEANING=1 ;;
      domain)  HAS_DOMAIN=1 ;;
      word)        FIXED=$((FIXED + 10)) ;;
      lang)        FIXED=$((FIXED + 6)) ;;
      source)      FIXED=$((FIXED + 10)) ;;
      seen)        FIXED=$((FIXED + 6)) ;;
      age)         FIXED=$((FIXED + 5)) ;;
      via)         FIXED=$((FIXED + 11)) ;;
      status)      FIXED=$((FIXED + 8)) ;;
      rating)      FIXED=$((FIXED + 8)) ;;
      example)     FIXED=$((FIXED + 42)) ;;
      context)     FIXED=$((FIXED + 42)) ;;
      note)        FIXED=$((FIXED + 32)) ;;
      *)           FIXED=$((FIXED + 12)) ;;
    esac
  done
  REMAIN=$((TERM_W - FIXED))
  [[ $REMAIN -lt 20 ]] && REMAIN=20
  if [[ $HAS_MEANING -eq 1 && $HAS_DOMAIN -eq 1 ]]; then
    [[ "$MEANING_W" == "auto" ]] && MEANING_W=$((REMAIN * 65 / 100))
    [[ "$DOMAIN_W" == "auto" ]] && DOMAIN_W=$((REMAIN * 35 / 100))
  elif [[ $HAS_MEANING -eq 1 ]]; then
    [[ "$MEANING_W" == "auto" ]] && MEANING_W=$REMAIN
  elif [[ $HAS_DOMAIN -eq 1 ]]; then
    [[ "$DOMAIN_W" == "auto" ]] && DOMAIN_W=$REMAIN
  else
    [[ "$MEANING_W" == "auto" ]] && MEANING_W=30
    [[ "$DOMAIN_W" == "auto" ]] && DOMAIN_W=25
  fi
  [[ "$MEANING_W" -lt 12 ]] 2>/dev/null && MEANING_W=12
  [[ "$DOMAIN_W" -lt 10 ]] 2>/dev/null && DOMAIN_W=10
fi

# Map sort spec → sort column + flags. voca.tsv 1-indexed:
#   1 word, 8 seen_count, 9 first_seen_at, 10 last_seen_at
case "$SORT_SPEC" in
  "last_seen desc")  SORT_K=10; SORT_FLAGS=r ;;
  "last_seen asc")   SORT_K=10; SORT_FLAGS="" ;;
  "first_seen desc") SORT_K=9;  SORT_FLAGS=r ;;
  "first_seen asc")  SORT_K=9;  SORT_FLAGS="" ;;
  "seen_count desc") SORT_K=8;  SORT_FLAGS=nr ;;
  "seen_count asc")  SORT_K=8;  SORT_FLAGS=n ;;
  "word asc")        SORT_K=1;  SORT_FLAGS="" ;;
  "word desc")       SORT_K=1;  SORT_FLAGS=r ;;
  *)                 SORT_K=10; SORT_FLAGS=r ;;
esac

ROWS=$(awk -F'\t' -v s="$STATUS" -v l="$LANG_FILTER" '
  NR == 1 { next }
  l != "" && l != "all" && tolower($2) != tolower(l) { next }
  s == "all"      { print; next }
  s == "active"   { if ($13 == "active" || $13 == "") print; next }
  $13 == s        { print }
' "$WORDS_TSV" | sort -t$'\t' -k${SORT_K},${SORT_K}${SORT_FLAGS} | head -n "$N")

if [[ -z "$ROWS" ]]; then
  if [[ -n "$LANG_FILTER" && "$LANG_FILTER" != "all" ]]; then
    echo "(no entries with status=$STATUS, lang=$LANG_FILTER)"
  else
    echo "(no entries with status=$STATUS)"
  fi
  exit 0
fi

COUNT=$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')

# Build header from configured columns
HEADER=""
for c in "${COLUMNS[@]}"; do
  [[ -n "$HEADER" ]] && HEADER+=$'\t'
  HEADER+="$c"
done

{
  printf '%s\n' "$HEADER"
  # perl with -CSDA = char-aware substr (awk substr is byte-based and mangles
  # multi-byte chars, which breaks BSD `column -t` on macOS).
  # %render dispatches per column name read from $ENV{COLUMNS}.
  printf '%s\n' "$ROWS" | \
    MEANING_W="$MEANING_W" DOMAIN_W="$DOMAIN_W" COLUMNS="${COLUMNS[*]}" \
    perl -CSDA -F'\t' -lane '
    use Time::Piece;
    BEGIN {
      sub fmt_age {
        my ($first, $last) = @_;
        return "-" if !$first || !$last;
        my $f = eval { Time::Piece->strptime($first, "%Y-%m-%d") };
        my $l = eval { Time::Piece->strptime($last, "%Y-%m-%d") };
        return "-" unless $f && $l;
        my $diff = $l - $f;
        return "-" if $diff < 0;
        return int($diff/60) . "m"          if $diff < 3600;
        return int($diff/3600) . "h"        if $diff < 86400;
        return int($diff/86400) . "d"       if $diff < 30*86400;
        return int($diff/(30*86400)) . "M";
      }
      sub trunc {
        my ($s, $w) = @_;
        return "-" unless defined $s && $s ne "";
        return length($s) > $w ? substr($s, 0, $w) : $s;
      }
      sub clean_domain {
        my $d = $_[0] // "";
        $d =~ s/^\[|\]$//g;
        $d =~ s/"//g;
        return $d eq "" ? "-" : $d;
      }
      sub or_dash {
        my $v = $_[0];
        return (defined $v && $v ne "") ? $v : "-";
      }
    }
    my $MW = $ENV{MEANING_W} || 30;
    my $DW = $ENV{DOMAIN_W} || 25;
    my @cols = split /\s+/, ($ENV{COLUMNS} || "");

    my %render = (
      word        => sub { $F[0]  // "-" },
      lang        => sub { or_dash($F[1]) },
      meaning     => sub { trunc($F[2], $MW) },
      example     => sub { trunc($F[3], 40) },
      context     => sub { trunc($F[4], 40) },
      source      => sub { or_dash($F[5]) },
      domain      => sub { trunc(clean_domain($F[6]), $DW) },
      seen        => sub { or_dash($F[7]) },
      first_seen  => sub { or_dash($F[8]) },
      last_seen   => sub { or_dash($F[9]) },
      via         => sub { or_dash($F[10]) },
      rating      => sub { or_dash($F[11]) },
      status      => sub { (defined $F[12] && $F[12] ne "") ? $F[12] : "active" },
      note        => sub { trunc($F[13], 30) },
      mastered_at => sub { or_dash($F[14]) },
      archived_at => sub { or_dash($F[15]) },
      age         => sub { fmt_age($F[8] // "", $F[9] // "") },
    );

    my @cells = map { exists $render{$_} ? $render{$_}->() : "?" } @cols;
    print join("\t", @cells);
  '
} | column -t -s $'\t'

echo
if [[ -n "$LANG_FILTER" && "$LANG_FILTER" != "all" ]]; then
  echo "Showing $COUNT (status=$STATUS, lang=$LANG_FILTER)"
else
  echo "Showing $COUNT (status=$STATUS)"
fi
