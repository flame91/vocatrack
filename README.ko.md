# voca — Claude Code Plugin

영어 / 일본어 / 한국어 어휘 추적기 + TestYourVocab 스타일 레벨 추정. 모든 데이터는 로컬 TSV에 저장되며 외부로 나가지 않음. Claude Code의 `/voca` 슬래시 커맨드로 접근.

## 설치

```text
/plugin marketplace add <이 repo의 git URL>
/plugin install voca@flame91-voca-marketplace
```

## 주요 기능

- `/voca add <단어>` — 의미·예문·컨텍스트·태그와 함께 기록
- `/voca list` / `/voca search <q>` / `/voca stats` — 컬렉션 조회
- `/voca level test [en|ja|ko]` — 3단계 적응형 어휘 추정 (Stage 1 + 2 + 3)
- `/voca queue` — 세션에서 자동 추출된 후보 단어 picker UI
- Stop hook으로 매 세션 종료 시 백그라운드에서 후보 자동 추출 (Haiku 호출, vocab.tsv와 자동 dedup)

> **Privacy:** Stop hook은 마지막 assistant turn (또는 수동 `full` 모드 시 전체 transcript) 을 로컬 `claude` CLI를 거쳐 Anthropic Haiku API로 보내 후보 단어를 추출함. 본인의 Anthropic 자격으로만 사용되며 제3자로는 전송되지 않음. 비활성화하려면 install 후 `~/.claude/settings.json` 에서 hook을 제거.

## 환경변수

| var | 기본값 | 용도 |
|---|---|---|
| `VOCA_LOCALE` | 시스템 locale (`ko`/`en`/`ja`, fallback `en`) | shell 결과 메시지 언어 |
| `VOCA_STATE_DIR` | `${CLAUDE_PLUGIN_DATA}` 또는 `~/.claude/state` | vocab.tsv / profile / config 위치 |

## 기존 설치(symlink 방식)에서 이관

기존에 `~/.claude/scripts/vocab/`, `~/.claude/skills/vocab/` 등을 수동으로 깔아 쓰던 경우, **state 파일** (`~/.claude/state/vocab*`) 을 plugin data dir로 옮길 수 있음:

```sh
bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-from-legacy.sh --dry-run
bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-from-legacy.sh
```

`~/.claude/` 안의 기존 script/skill/command 파일은 **자동 삭제하지 않음** — plugin 동작 확인 후 직접 삭제.

## 의존성

- `bash` 4+, `jq`, `awk`, `sed`, `column`, `python3`
- macOS / Linux / WSL

## v1 제약

- SKILL.md / voca.md (AskUserQuestion 라벨)는 한국어 유지. 결과 메시지 라인만 `VOCA_LOCALE` 적용. 전체 UI i18n은 v2 예정.
- 어휘 풀 업데이트는 `tools/_curate.py` 빌드 (kiwipiepy 위한 별도 Python venv 필요).

## 라이선스

CC BY-SA 4.0 — [LICENSE](./LICENSE) + [NOTICE](./NOTICE) 참조.
