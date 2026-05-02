# voca -- Claude Code Plugin

영어 / 일본어 / 한국어를 위한 로컬 우선 어휘 추적기. TestYourVocab 스타일 레벨 추정 포함.

> English: [README.md](./README.md) | 日本語: [README.ja.md](./README.ja.md)

## 설치

```text
/plugin marketplace add https://github.com/flame91/vocatrack
/plugin install voca@flame91-voca-marketplace
```

## 기능

| 커맨드 | 설명 |
|---|---|
| `/voca add <단어>` | 의미, 예문, 컨텍스트, 태그와 함께 기록 |
| `/voca list` | 최근 어휘 목록 테이블 보기 |
| `/voca search <q>` | 단어/의미/예문/컨텍스트 대소문자 무시 검색 |
| `/voca stats` | 대시보드 (레벨, 라이프사이클, 활동, hook 정밀도) |
| `/voca review` | 미평가 활성 단어 대화형 리뷰 |
| `/voca rate <단어>` | 단어 평가: memorized, learning, unsure |
| `/voca archive <단어>` | 단어 아카이브 |
| `/voca master <단어>` | 단어를 mastered로 승격 |
| `/voca restore <단어>` | 아카이브/mastered 단어를 active로 복원 |
| `/voca level test [en\|ja\|ko]` | 3단계 적응형 어휘량 추정 |
| `/voca queue` | 자동 추출된 후보 단어 picker UI |
| `/voca config` | 대화형 설정 |
| `/voca domain` | 도메인 태그 레지스트리 관리 (조회 / 추가 / 삭제) |
| `/voca source` | 소스 태그 레지스트리 관리 (조회 / 추가 / 삭제) |
| `/voca reclassify` | 기존 단어를 현재 컨벤션으로 재태깅 |

**Stop hook**이 매 세션 종료 시 백그라운드에서 Haiku를 호출하여 후보 단어를 자동 추출하고 기존 단어장과 중복 제거합니다.

## 프라이버시

Stop hook은 로컬 `claude` CLI를 통해 Anthropic Haiku API를 호출합니다. 본인의 Anthropic 자격 증명만 사용되며 제3자로 전송되지 않습니다.

## 환경변수

| 변수 | 기본값 | 용도 |
|---|---|---|
| `VOCA_LOCALE` | 시스템 locale (`ko`/`en`/`ja`, fallback `en`) | shell 스크립트 결과 메시지 언어 |
| `VOCA_STATE_DIR` | `${CLAUDE_PLUGIN_DATA}` 또는 `~/.claude/state` | voca.tsv, profile, config 저장 위치 |
| `VOCA_CONFIG_PATH` | `${VOCA_STATE_DIR}/voca-config.json` | 설정 파일 경로 |

## 기존 설치에서 이관

마이그레이션 스크립트가 기존 `vocab*` 파일을 새 `voca*` 이름으로 매핑합니다:

```sh
bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-from-legacy.sh --dry-run
bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-from-legacy.sh
```

## 의존성

- `bash` 4+, `jq`, `awk`, `sed`, `column`, `python3` (hook 타임스탬프용)
- macOS / Linux / WSL

## 제약 사항 (v0.1.3)

- shell 스크립트 출력은 `VOCA_LOCALE`을 통해 ko/en/ja로 로컬라이즈됩니다.
- SKILL.md UI 문자열 (AskUserQuestion)은 주 언어 설정을 통해 locale 인식 렌더링을 지원합니다.
- 어휘 풀 업데이트에는 `tools/_curate.py`가 필요합니다 (별도 Python venv).

## 라이선스

CC BY-SA 4.0 -- [LICENSE](./LICENSE) 및 [NOTICE](./NOTICE) 참조.
