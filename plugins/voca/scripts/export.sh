#!/usr/bin/env bash
# /voca export [--format=csv|anki|json|md] [--status=active|mastered|archived|all] [--lang=en|ja|ko|all]
# Exports voca.tsv entries to stdout in the chosen format.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

FORMAT="csv"
STATUS_FILTER="active"
LANG_FILTER="all"

for arg in "$@"; do
  case "$arg" in
    --format=*) FORMAT="${arg#--format=}" ;;
    --status=*) STATUS_FILTER="${arg#--status=}" ;;
    --lang=*)   LANG_FILTER="${arg#--lang=}" ;;
  esac
done

{
  case "$FORMAT" in
    csv)
      echo "word,lang,meaning,example,context,source,domain,seen_count,first_seen_at,last_seen_at,added_via,user_rating,status,user_note,mastered_at,archived_at"
      awk -F'\t' -v OFS=',' \
        $AWK_COL_VARS \
        -v sf="$STATUS_FILTER" -v lf="$LANG_FILTER" '
        NR == 1 { next }
        sf != "all" && $C_STATUS != sf { next }
        lf != "all" && $C_LANG != lf { next }
        {
          for (i = 1; i <= NF; i++) {
            gsub(/"/, "\"\"", $i)
            if ($i ~ /,/) $i = "\"" $i "\""
          }
          print
        }
      ' "$WORDS_TSV"
      ;;
    anki)
      awk -F'\t' -v OFS='\t' \
        $AWK_COL_VARS \
        -v sf="$STATUS_FILTER" -v lf="$LANG_FILTER" '
        NR == 1 { next }
        sf != "all" && $C_STATUS != sf { next }
        lf != "all" && $C_LANG != lf { next }
        {
          tags = $C_LANG
          d = $C_DOMAIN
          gsub(/[\[\]"]/, "", d)
          if (d != "") tags = tags " " d
          front = $C_WORD
          back = $C_MEANING
          if ($C_EXAMPLE != "") back = back "\n" $C_EXAMPLE
          print front "\t" back "\t" tags
        }
      ' "$WORDS_TSV"
      ;;
    json)
      awk -F'\t' \
        $AWK_COL_VARS \
        -v sf="$STATUS_FILTER" -v lf="$LANG_FILTER" '
        function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s); return s }
        NR == 1 { next }
        sf != "all" && $C_STATUS != sf { next }
        lf != "all" && $C_LANG != lf { next }
        {
          if (n++) printf ","
          printf "{\"word\":\"%s\",\"lang\":\"%s\",\"meaning\":\"%s\",\"example\":\"%s\",\"domain\":%s,\"source\":\"%s\",\"status\":\"%s\",\"rating\":\"%s\"}", \
            esc($C_WORD), esc($C_LANG), esc($C_MEANING), esc($C_EXAMPLE), \
            ($C_DOMAIN != "" ? $C_DOMAIN : "[]"), esc($C_SOURCE), esc($C_STATUS), esc($C_RATING)
        }
        BEGIN { printf "[" }
        END { print "]" }
      ' "$WORDS_TSV"
      ;;
    md)
      echo "| Word | Lang | Meaning | Example | Status | Rating |"
      echo "|------|------|---------|---------|--------|--------|"
      awk -F'\t' \
        $AWK_COL_VARS \
        -v sf="$STATUS_FILTER" -v lf="$LANG_FILTER" '
        NR == 1 { next }
        sf != "all" && $C_STATUS != sf { next }
        lf != "all" && $C_LANG != lf { next }
        {
          w = $C_WORD; gsub(/\|/, "\\|", w)
          m = $C_MEANING; gsub(/\|/, "\\|", m)
          e = $C_EXAMPLE; gsub(/\|/, "\\|", e)
          printf "| %s | %s | %s | %s | %s | %s |\n", w, $C_LANG, m, e, $C_STATUS, $C_RATING
        }
      ' "$WORDS_TSV"
      ;;
    *)
      echo "Unknown format: $FORMAT (use csv, anki, json, md)" >&2
      exit 1
      ;;
  esac
}
