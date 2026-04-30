#!/usr/bin/env bash
# /vocab config Optimize — 가용 터미널 폭에 맞는 list.columns/widths 추천
#
# usage: optimize.sh <available_cols>
# stdout (line 1): JSON
#   {"columns":[...],"meaning_w":N,"domain_w":N,"total_w":N,
#    "available":N,"dropped":[...]}
# stdout (after blank line): 권장 컬럼 헤더를 그 폭으로 padding한 1행 preview
#
# BSD `column -t -s '\t'`은 컬럼 사이 공백을 2칸으로 넣음 — total 계산 시 동일 가정.
set -uo pipefail

AVAIL="${1:-}"
if [[ -z "$AVAIL" || ! "$AVAIL" =~ ^[0-9]+$ ]]; then
  echo "usage: optimize.sh <available_cols>" >&2
  exit 1
fi
if (( AVAIL < 30 )); then
  echo "available_cols too small: $AVAIL (minimum 30)" >&2
  exit 1
fi

# 고정 폭 (헤더 + 데이터 ~p95). bash 3.2에 assoc array 없으므로 함수로.
fixed_w() {
  case "$1" in
    word)   echo 22 ;;
    lang)   echo 4 ;;
    source) echo 8 ;;
    seen)   echo 4 ;;
    age)    echo 4 ;;
    via)    echo 9 ;;
    status) echo 6 ;;
    rating) echo 9 ;;
    *)      echo 10 ;;
  esac
}

# Optimize 후보 컬럼 — 우선순위 (앞부터 유지, 뒤부터 drop)
PRIORITY=(word lang meaning status age seen via source domain rating)
# 코어 4개는 절대 drop 안 함
CORE=(word lang meaning status)
# Drop 순서 (꼬리부터)
DROP_ORDER=(rating domain source via seen age)

PADDING=2  # column -t 사이 간격

calc_total() {
  local mw="$1" dw="$2"; shift 2
  local cols=("$@")
  local sum=0 c
  for c in "${cols[@]}"; do
    case "$c" in
      meaning) sum=$((sum + mw)) ;;
      domain)  sum=$((sum + dw)) ;;
      *)       sum=$((sum + $(fixed_w "$c"))) ;;
    esac
  done
  local n=${#cols[@]}
  if (( n > 1 )); then
    sum=$((sum + (n - 1) * PADDING))
  fi
  echo "$sum"
}

contains() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# 시작 상태
COLUMNS=("${PRIORITY[@]}")
MW=20
DW=15
DROPPED=()

# 1) 폭 초과면 꼬리부터 drop
total=$(calc_total "$MW" "$DW" "${COLUMNS[@]}")
for victim in "${DROP_ORDER[@]}"; do
  (( total <= AVAIL )) && break
  # COLUMNS에서 victim 제거
  new_cols=()
  for c in "${COLUMNS[@]}"; do
    [[ "$c" == "$victim" ]] && { DROPPED+=("$victim"); continue; }
    new_cols+=("$c")
  done
  COLUMNS=("${new_cols[@]}")
  total=$(calc_total "$MW" "$DW" "${COLUMNS[@]}")
done

# 2) 그래도 초과면 meaning_W를 12까지 줄이고 domain도 동기화
while (( total > AVAIL )) && (( MW > 12 )); do
  MW=$((MW - 2))
  DW=$((MW - 5)); (( DW < 10 )) && DW=10
  total=$(calc_total "$MW" "$DW" "${COLUMNS[@]}")
done

# 3) 최후 수단 — 코어 4개만 남길 때까지 drop (CORE에 없는 것만)
while (( total > AVAIL )) && (( ${#COLUMNS[@]} > ${#CORE[@]} )); do
  # 마지막에서부터 코어 아닌 것 찾아 drop
  removed=0
  for ((i=${#COLUMNS[@]}-1; i>=0; i--)); do
    c="${COLUMNS[$i]}"
    if ! contains "$c" "${CORE[@]}"; then
      DROPPED+=("$c")
      COLUMNS=("${COLUMNS[@]:0:$i}" "${COLUMNS[@]:$((i+1))}")
      removed=1
      break
    fi
  done
  (( removed == 0 )) && break
  total=$(calc_total "$MW" "$DW" "${COLUMNS[@]}")
done

# 4) 슬랙이 남으면 meaning_W를 키움 (최대 60), domain도 따라감 (최대 55)
if contains "meaning" "${COLUMNS[@]}"; then
  while :; do
    slack=$((AVAIL - total))
    (( slack < 4 )) && break
    (( MW >= 60 )) && break
    if (( slack >= 10 )); then
      MW=$((MW + 4))
    else
      MW=$((MW + 2))
    fi
    (( MW > 60 )) && MW=60
    if contains "domain" "${COLUMNS[@]}"; then
      DW=$((MW - 5)); (( DW > 55 )) && DW=55
    fi
    total=$(calc_total "$MW" "$DW" "${COLUMNS[@]}")
    if (( total > AVAIL )); then
      # 한 단계 되돌림
      MW=$((MW - 2))
      if contains "domain" "${COLUMNS[@]}"; then
        DW=$((MW - 5)); (( DW < 10 )) && DW=10
      fi
      total=$(calc_total "$MW" "$DW" "${COLUMNS[@]}")
      break
    fi
  done
fi

# JSON 출력
COLS_JSON=$(printf '%s\n' "${COLUMNS[@]}" | jq -R . | jq -s -c .)
DROPPED_JSON=$(if (( ${#DROPPED[@]} > 0 )); then
  printf '%s\n' "${DROPPED[@]}" | jq -R . | jq -s -c .
else
  echo '[]'
fi)

jq -n -c \
  --argjson cols "$COLS_JSON" \
  --argjson dropped "$DROPPED_JSON" \
  --argjson mw "$MW" --argjson dw "$DW" \
  --argjson total "$total" --argjson avail "$AVAIL" \
  '{columns:$cols, meaning_w:$mw, domain_w:$dw, total_w:$total, available:$avail, dropped:$dropped}'

# preview — 헤더 라인을 권장 폭으로 padding
echo
preview=""
first=1
for c in "${COLUMNS[@]}"; do
  case "$c" in
    meaning) w="$MW" ;;
    domain)  w="$DW" ;;
    *)       w=$(fixed_w "$c") ;;
  esac
  if (( first == 1 )); then
    first=0
  else
    preview+="  "  # padding
  fi
  preview+=$(printf "%-${w}s" "$c")
done
echo "$preview"
echo "($total / $AVAIL cols, dropped: ${DROPPED[*]:-none})"
