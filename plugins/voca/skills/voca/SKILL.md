---
name: voca
description: Personal vocabulary tracker — adds, queries, rates words; manages tag options (domain/source); processes the Stop-hook candidate queue via interactive picker; scans the current session to backfill missed candidates. Backed by local TSV files. Use when the user says things like "이 단어 저장해줘", "방금 그 단어 모르겠어", "지금까지 추가한 단어 보여줘", "/voca setup/add/list/review/rate/archive/master/restore/domain/source/queue/scan", "단어장 보여줘", "infra 태그 추가해줘", "큐 비워줘", "MCP만 추가하고 나머지는 무시", "지금까지 대화 다시 훑어줘", "이 세션 단어 모아줘", "세션 스캔해줘", or when the user explicitly asks to record a word, manage vocab tags, accept/reject candidates, or backfill candidates from the current conversation.
---

# Voca Tracker

Local-first vocabulary collection backed by TSV files. No external services, no auth required.

## Path Variables

- `${CLAUDE_PLUGIN_ROOT}` — read-only plugin install dir (scripts, wordlists, messages, data)
- `${CLAUDE_PLUGIN_DATA}` — per-user writable state dir (voca.tsv, profile, candidates, config)

## Prerequisites

Before any workflow below (except **Setup workflow** itself), run the setup guard:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-guard.sh require
```

If the script prints anything on stdout, pass it through verbatim and **stop**. Otherwise (silent) proceed with the requested command. The script handles locale-aware message resolution itself, so the model does not need to look up `[setup.required]` in the UI Strings table.

## UI Strings

Resolve the user's UI locale at the start of each interactive workflow:
```bash
UI_LANG=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh primary_lang)
```
Use the corresponding column below for all AskUserQuestion text. Fallback to `en` if unknown.

| key | ko | en | ja |
|---|---|---|---|
| review.question_suffix | 외웠어? | Memorized? | 覚えた？ |
| review.learning | 아직 학습 중 | Still learning | まだ学習中 |
| review.unsure | 패스 | Pass | パス |
| review.continue | %d개 더 평가하시겠어요? | Rate %d more? | あと%d語を評価しますか？ |
| queue.empty | 큐가 비어 있습니다. /voca scan 으로 추출을 시작하세요. | Queue is empty. Run /voca scan to extract candidates. | キューが空です。/voca scan で抽出を開始してください。 |
| queue.no_new | 큐에 새 단어가 없습니다 (전체 큐: %d개). | No new words in queue (total: %d). | キューに新しい単語はありません (全体: %d語)。 |
| queue.question | 추가할 단어를 골라주세요 (선택 안 한 항목은 reject로 처리됩니다). | Select words to add (unselected items will be rejected). | 追加する単語を選んでください (未選択はreject)。 |
| queue.select_all_known | 이 페이지의 모든 단어를 알고 있음 | I know all the words on this page | このページの全単語を知っています |
| queue.select_all_desc | 체크 안 한 나머지 단어를 '이미 알고 있음'으로 reject 처리 | Reject remaining unchecked words as 'already known' | チェックしていない残りを「既知」としてreject |
| queue.continue | 남은 %d개 더 처리할까요? | Process %d more? | 残り%d語を処理しますか？ |
| manage.select_question | 관리할 단어를 선택하세요 | Select words to act on | 操作する単語を選んでください |
| manage.no_selection | 선택된 단어 없음 — 종료. | Nothing selected — done. | 選択なし — 終了。 |
| manage.action_question | 선택한 %d개 단어에 적용할 작업은? | What action for the %d selected word(s)? | 選択した %d 語にどの操作を適用？ |
| manage.action.memorized / _desc | memorized / 암기 완료 → mastered 자동 승격 | memorized / Mark as memorized → auto-promote to mastered | memorized / 暗記済 → mastered に自動昇格 |
| manage.action.learning / _desc | learning / 아직 학습 중 (active 유지) | learning / Still learning, keep active | learning / まだ学習中 (active のまま) |
| manage.action.unsure / _desc | unsure / 일단 패스, 나중에 재검토 | unsure / Pass for now, revisit later | unsure / いったんパス、後で再確認 |
| manage.action.master / _desc | master / mastered로 수동 승격 (rating 변경 없음) | master / Promote to mastered (no rating change) | master / 手動で mastered に昇格 (rating は変更しない) |
| manage.action.archive / _desc | archive / 소프트 삭제 (status=archived) | archive / Soft-delete (status=archived) | archive / ソフト削除 (status=archived) |
| manage.action.cancel / _desc | cancel / 아무 작업도 하지 않고 종료 | cancel / Do nothing, exit | cancel / 何もせず終了 |
| manage.cancelled | 관리 취소. | Manage cancelled. | 管理キャンセル。 |
| manage.continue | 남은 %d개도 관리할까요? | Manage %d more? | 残り %d 語も管理しますか？ |
| manage.done | 완료 — %d개 단어에 %s 적용. | Done — applied %s to %d word(s). | 完了 — %d 語に %s を適用。 |
| setup.lang_question | 구사 가능한 언어를 선택하세요 | Select languages you speak | 話せる言語を選択してください |
| setup.primary_question | meaning을 어떤 언어로 받을까요? | Which language for meanings? | meaningをどの言語で表示しますか？ |
| config.current_marker |  (현재값) |  (current) |  (現在値) |
| config.section_question | 어떤 설정을 조정할까요? | Which settings to adjust? | どの設定を調整しますか？ |
| config.list_columns | List 컬럼 선택 | List column selection | Listカラム選択 |
| config.list_columns_desc | /voca list에 표시할 컬럼 | Columns to show in /voca list | /voca listに表示するカラム |
| config.list_options | List 옵션 | List options | Listオプション |
| config.list_options_desc | 기본 N · 상태 필터 · 정렬 · meaning 너비 | Default N · status filter · sort · meaning width | デフォルトN · ステータスフィルター · ソート · meaning幅 |
| config.picker_scan | Picker / Scan | Picker / Scan | Picker / Scan |
| config.picker_scan_desc | 큐 picker 라운드 크기, 스캔 모델, dedup | Queue picker round size, scan model, dedup | キューpickerラウンドサイズ、スキャンモデル、dedup |
| config.primary_optimize | 주 언어 · Optimize | Primary lang · Optimize | 主言語 · Optimize |
| config.primary_optimize_desc | meaning 출력 언어 변경 또는 컬럼·폭 자동 추천 | Change meaning language or auto-recommend columns/widths | meaning出力言語変更またはカラム・幅自動推薦 |
| config.sub_question | 이 메뉴에서 무엇을 할까요? | What would you like to do? | このメニューで何をしますか？ |
| config.primary_change | 주 언어 변경 | Change primary language | 主言語変更 |
| config.primary_change_desc | meaning · hint 생성 언어 (현재: %s) | Language for meaning · hint (current: %s) | meaning · hint の言語 (現在: %s) |
| config.optimize_recommend | Optimize 자동 추천 | Auto-recommend Optimize | Optimize自動推薦 |
| config.optimize_recommend_desc | 터미널 스크린샷으로 컬럼·폭 추천 | Recommend columns/widths from terminal screenshot | ターミナルスクリーンショットからカラム・幅推薦 |
| config.primary_no_profile | 먼저 /voca level 로 언어 프로필을 만들어주세요. | Create a language profile first with /voca level. | まず /voca level で言語プロファイルを作成してください。 |
| optimize.instruction | 터미널을 평소 사용하는 너비로 띄운 뒤, /voca list 결과가 보이는 스크린샷을 다음 메시지에 첨부해주세요. | Open your terminal at its normal width and attach a screenshot showing /voca list output in your next message. | ターミナルを通常幅で開き、/voca list の結果が表示されたスクリーンショットを次のメッセージに添付してください。 |
| optimize.confirm | 이 추천을 적용할까요? (%dcols 가정) | Apply this recommendation? (%dcols assumed) | この推薦を適用しますか？ (%dcols想定) |
| optimize.apply | 적용 | Apply | 適用 |
| optimize.apply_desc | 위 columns/widths로 저장 | Save with above columns/widths | 上記のcolumns/widthsで保存 |
| optimize.widen | meaning 폭 +6 | meaning width +6 | meaning幅 +6 |
| optimize.widen_desc | 뜻 컬럼을 더 넓게 | Widen meaning column | meaningカラムを広く |
| optimize.narrow | meaning 폭 −6 | meaning width −6 | meaning幅 −6 |
| optimize.narrow_desc | 여백을 더 확보 | More margin space | 余白を確保 |
| optimize.cancel | 취소 | Cancel | キャンセル |
| optimize.cancel_desc | 변경하지 않고 종료 | Exit without changes | 変更せず終了 |
| optimize.cancelled | Optimize 취소. | Optimize cancelled. | Optimizeキャンセル。 |
| reclassify.confirm | %d개 reclassify 진행할까요? (y/n) | Reclassify %d words? (y/n) | %d語をreclassifyしますか？ (y/n) |
| lang.ko | 한국어 | Korean | 韓国語 |
| lang.ja | 일본어 | Japanese | 日本語 |
| lang.en | 영어 | English | 英語 |
| lang.ko_desc | ko 측정 | ko measurement | ko 測定 |
| lang.ja_desc | ja 측정 | ja measurement | ja 測定 |
| lang.en_desc | en 측정 | en measurement | en 測定 |
| terminal.width_question | 대략적 터미널 폭은? | Approximate terminal width? | ターミナル幅はおよそ？ |
| setup.required | 먼저 /voca setup을 실행해주세요. | Run /voca setup first. | まず /voca setup を実行してください。 |
| setup.already_done | 초기 설정이 이미 완료되었습니다. /voca config로 변경할 수 있습니다. | Setup already completed. Use /voca config to make changes. | 初期設定は完了済みです。/voca config で変更できます。 |
| setup.scan_model_question | 단어 추출에 사용할 모델을 선택하세요. | Select the model for word extraction. | 単語抽出に使用するモデルを選択してください。 |
| setup.complete | 초기 설정 완료! | Setup complete! | 初期設定完了！ |
| scan.spawned | 전체 대화 추출을 시작했습니다 (~30-60s). 완료 후 /voca queue 실행. | Spawned full-transcript extraction (~30-60s). Run /voca queue when ready. | 全会話の抽出を開始しました (~30-60秒)。完了後 /voca queue を実行。 |
| scan.already_running | 추출이 이미 진행 중입니다. 잠시 후 /voca queue 실행. | Extraction already in progress. Run /voca queue shortly. | 抽出はすでに進行中です。しばらく後に /voca queue を実行。 |
| scan.status_running | 추출기 실행 중. | Extractor running. | 抽出器実行中。 |
| scan.status_idle | 추출기 대기 중. | Extractor idle. | 抽出器待機中。 |
| scan.status_queue | 큐: %d개 대기 중. | Queue: %d pending. | キュー: %d件待機中。 |

## Storage

- `${CLAUDE_PLUGIN_DATA}/voca.tsv` — main word entries (16 columns; see cheat sheet)
- `${CLAUDE_PLUGIN_DATA}/voca-candidates-log.tsv` — Stop hook telemetry (8 columns)
- `${CLAUDE_PLUGIN_DATA}/voca-candidates.json` — pending Stop-hook candidate queue (JSON)
- `${CLAUDE_PLUGIN_DATA}/domains.txt`, `sources.txt` — tag option registries (plain text, `name color` per line)

The user can edit `voca.tsv` directly in VS Code/Numbers/Excel — keep the header row and 16 columns intact.

## Candidate queue

The Stop hook writes auto-detected candidates to `voca-candidates.json` and surfaces them via additionalContext. Format:

```json
{ "pending": [ {"word": "ephemeral", "lang": "en", "hint": "...", "extracted_at": "...", "hook_latency_ms": 234} ] }
```

Hook also dedups against two sources before queuing:
1. **`voca.tsv`** — any word already tracked (regardless of status or rating). User has already chosen to record it.
2. **`voca-candidates-log.tsv` rows where `rejected_reason == "user marked as already known via picker"`** — words the user explicitly dismissed via the page-wide `[queue.select_all_known]` option. These act as a virtual "already-known archive" so the user is never re-prompted for the same word they previously declared they know. (Plain `skip` rejections do NOT enter the skip-list — those may legitimately resurface later.)

## Workflows

> **All Notion-era MCP calls (`notion-search`, `notion-create-pages`, `notion-update-page`, `notion-update-data-source`, `notion-fetch`) are gone.** Every operation now runs through `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh`. The slash-command (`voca.md`) auto-routes simple subcommands to scripts; the workflows below cover what to do for inference-heavy commands.

### Add a word (`/voca add <word>` or natural language)

1. Determine the word. If the user said "그 단어" / "방금 단어", check the candidate queue first; otherwise extract from their message.
1a. Resolve the user's primary language **once at the start** of the workflow:
    `PRIMARY=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh primary_lang_name)` (returns e.g. `Korean (한국어)` / `English` / `Japanese (日本語)`; fallback `Korean (한국어)`). Use `$PRIMARY` for the `meaning` field below.
2. Infer fields from the conversation:
   - `lang`: en/ja/ko/mixed/other
   - `meaning`: 1 line, in `$PRIMARY` (the user's primary language)
   - `example`: 1 sentence, in original language
   - `context`: 1-2 line excerpt of the surrounding conversation
   - `domain`: subset of options listed in `domains.txt` (use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/domain-list.sh` if unsure)
   - `source`: closest single tag from `sources.txt`
   - `added_via`: `manual` / `auto-hook` (from queue) / `review`
3. Build a JSON object and pipe it to `add.sh`:
   ```bash
   echo '{"word":"ephemeral","lang":"en","meaning":"...","example":"...","context":"...","source":"language","domain":["language"],"added_via":"manual"}' \
     | bash ${CLAUDE_PLUGIN_ROOT}/scripts/add.sh
   ```
   `add.sh` handles dedup automatically (case-insensitive). Duplicates increment `seen_count` and update `last_seen_at`.
4. If the word came from the candidate queue, also remove it from `voca-candidates.json` (jq with `del(...)`) and append a row to `voca-candidates-log.tsv` with `accepted=1`, `command_used=voca-add`.
5. Reply with the 1-line confirmation that `add.sh` already printed (e.g., `Added "ephemeral" — 잠시 동안만 존재하는, 일시적인.`). **Do not echo the JSON or paraphrase the script output.**

### List recent (`/voca list [N] [--status=...] [--lang=...] [--manage|-m]`)

Handled by `voca.md` fast-path (`list.sh`). The script renders a table; pass it through verbatim.

- `--status` filter: `active` (default) / `mastered` / `archived` / `all`
- `--lang` filter: `en` / `ja` / `ko` / `mixed` / `other` / `all` (omitted = no filter, same as `all`). Default is the value of `list.default_lang` in `voca-config.json` if set.
- `--manage` / `-m`: after the table, enter the **Manage** picker flow (see below).
- `--json`: emit filtered rows as a JSON array (`[{word, lang, meaning, rating, status}]`). Used internally by the Manage flow; not user-facing.

### Manage (`/voca list --manage` / `-m`)

AskUserQuestion-based bulk action picker. Runs **after** the table has already been printed by `list.sh` (with `--manage` consumed and ignored).

1. Resolve `UI_LANG=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh primary_lang)`.
2. Fetch the same row set as JSON, passing the same filters:
   ```bash
   ROWS_JSON=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/list.sh --json $FILTER_ARGS)
   N=$(printf '%s' "$ROWS_JSON" | jq 'length')
   ```
   `$FILTER_ARGS` is the original `$ARGUMENTS` with `--manage` and `-m` stripped. If `N == 0`, stop (the table already showed `(no entries...)`).
3. **Picker round** — take **up to 16** rows for this round. Build **one** AskUserQuestion call (`multiSelect: true` on each question):
   - Distribute the words across **up to 4 questions** of **2–4 word-options each** (AskUserQuestion enforces `minItems: 2` per question). Suggested distribution: N≤4 → 1q; N=5 → 3+2; N=6 → 3+3; N=7 → 4+3; N=8 → 4+4; N=9 → 3+3+3; N=10 → 4+3+3; N=11 → 4+4+3; N=12 → 4+4+4; N=13 → 4+3+3+3; N=14 → 4+4+3+3; N=15 → 4+4+4+3; N=16 → 4+4+4+4. **N=1 edge case**: skip this step, set `SELECTED=[<word>]` directly, jump to step 4.
   - Each option: `{label: "<word>", description: "<lang> · <meaning truncated to ~60 chars>"}`.
   - `question`: `[manage.select_question]` (same on every question).
   - `header`: `Manage` (truncated per-question if needed).
4. Collect `SELECTED` = union of selected labels across all questions. If empty → reply `[manage.no_selection]` and stop.
5. **Action question** — single AskUserQuestion (`multiSelect: false`):
   - `question`: `[manage.action_question]` (with `%d` = `len(SELECTED)`)
   - `header`: `Action`
   - `options` (in this order):
     1. `{label:"[manage.action.memorized]", description:"[manage.action.memorized_desc]"}`
     2. `{label:"[manage.action.learning]",  description:"[manage.action.learning_desc]"}`
     3. `{label:"[manage.action.unsure]",    description:"[manage.action.unsure_desc]"}`
     4. `{label:"[manage.action.master]",    description:"[manage.action.master_desc]"}`
     5. `{label:"[manage.action.archive]",   description:"[manage.action.archive_desc]"}`
     6. `{label:"[manage.action.cancel]",    description:"[manage.action.cancel_desc]"}`
6. **Dispatch** based on the chosen action — for each `word` in `SELECTED`:
   - `memorized` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/rate.sh "$word" memorized`
   - `learning`  → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/rate.sh "$word" learning`
   - `unsure`    → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/rate.sh "$word" unsure`
   - `master`    → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/master.sh "$word"`
   - `archive`   → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/archive.sh "$word"`
   - `cancel`    → reply `[manage.cancelled]` and stop.
   Capture stdout from each script; suppress per-word echoes from the user-facing reply (the summary in step 7 covers the result).
7. Print **one line**: `[manage.done]` filled with the action label and the count of words processed (e.g., `Done — applied archive to 3 word(s).`).
8. **Pagination** — if more than 16 rows existed at step 2 and rows remain unprocessed, ask `[manage.continue]` (plain text, no GUI) with `%d` = remaining count. If the user assents, recurse from step 3 with the next batch.

### Review (`/voca review`)

Use **AskUserQuestion** for clickable rating UI.

1. Fetch candidates: `awk -F'\t' 'NR>1 && ($13=="active" || $13=="") && ($12==""||$12=="learning"||$12=="unsure")' ${CLAUDE_PLUGIN_DATA}/voca.tsv | sort -t$'\t' -k8,8nr | head -16` (sort by `seen_count` desc, take top 16).
2. Take **up to 4 words** at a time. Build one AskUserQuestion call with up to 4 questions, one per word:
   - `question`: `"<word>" — <meaning> — [review.question_suffix]`
   - `header`: word truncated to 12 chars
   - `multiSelect`: false
   - `options`: `[{label:"memorized", description:"<example>"}, {label:"learning", description:"[review.learning]"}, {label:"unsure", description:"[review.unsure]"}]`
3. After submission, for each rated word: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/rate.sh <word> <rating>`.
4. If unrated words remain, ask `[review.continue]` (text, not GUI).

### Rate (`/voca rate <word> <memorized|learning|unsure> [note]`)

Just `bash ${CLAUDE_PLUGIN_ROOT}/scripts/rate.sh "$word" "$rating" "$note"`. The script auto-promotes to `mastered` when the rating is `memorized`.

### Archive / Master / Restore

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/archive.sh "$word"` / `master.sh` / `restore.sh`. Pass through the 1-line confirmation.

### Manage tag options — `domain` / `source`

- list: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/domain-list.sh` (handled by fast-path)
- add: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/domain-add.sh <name> [color]`
- remove: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/domain-remove.sh <name>` (also strips the tag from any matching row in `voca.tsv`)
- same pattern for `source`

Allowed colors: gray, brown, orange, yellow, green, blue, purple, pink, red, default.

### Queue — `/voca queue` (single entry point)

`/voca queue` is the only queue subcommand. It launches the **Candidates Picker UI** (AskUserQuestion). Selection happens interactively; the only flag is `--flush` (clear the queue without a picker).

**`--flush` shortcut**: If the arguments contain `--flush`, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/queue-clear.sh`, pass through its 1-line confirmation, and stop. Do not proceed to the picker flow below.

> **Execution mode (hybrid)**: AskUserQuestion can only render its UI from the main session — a subagent cannot prompt the user. So `/voca queue` is split:
> - **Main context** runs steps 1–3 (single prep-round Bash call → AskUserQuestion picker). The prep call also handles the setup guard, so the global setup check at the top of this skill is **skipped** for `/voca queue` to avoid a redundant Bash round-trip.
> - **A general-purpose subagent** runs the remaining steps (per-accept inference + `add.sh`, per-reject log append, queue cleanup, 1-line summary). The subagent receives the selections + round payload via its prompt and never calls AskUserQuestion.
>
> This isolates the heaviest token cost (per-word inference for `add`) from the main conversation while keeping the picker UI functional. The command .md routing carries the orchestration template.

**Flow:**

1. **Prepare round (single Bash call)**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/queue-prepare-round.sh`. This atomically performs the setup guard, queue read, dedup, `shown:false` filter, and marks the next ≤15 candidates `shown:true` (persisting immediately so a dismiss-without-response still "consumes" the show). Output is JSON:
   ```
   {"status":"ok","pending_total":N,"round":[{word,lang,hint},...],"remaining_unshown":M}
   {"status":"setup_required","message":"<localized>"}
   {"status":"empty","pending_total":0,"message":"<localized>"}
   {"status":"no_new","pending_total":N,"message":"<localized>"}
   ```
2. **Branch**: if `status != "ok"` → print `.message` verbatim and stop (rationale for `no_new`: the user does not want to be re-prompted for candidates they already saw and dismissed). Otherwise continue to picker. Do NOT auto-spawn the extractor on `empty` — the user must run `/voca scan` explicitly.
3. **Picker** — Distribute `round` into AskUserQuestion questions. One AskUserQuestion call can pack max 4 questions × 4 options = 16 slots; one slot is reserved for the `[queue.select_all_known]` option (max 15 word-options per round). Build **one** AskUserQuestion call with multiple questions (`multiSelect: true` on each):
   - Distribute the N candidates into questions of up to 4 word-options each, in order. Append one extra option `[queue.select_all_known]` (description: `[queue.select_all_desc]`) at the **end of the last question**.
   - **`minItems: 2` guard**: if the last question would end up with the `[queue.select_all_known]` option alone (1 option), pull one word from the previous question into the last one so each question has ≥ 2 options. Concretely:
     - N=1 → `q0=[A, ALL]`
     - N=3 → `q0=[A, B, C, ALL]`
     - N=4 → `q0=[A, B, C], q1=[D, ALL]` (4-1 redistribution)
     - N=7 → `q0=[A,B,C,D], q1=[E,F,G, ALL]`
     - N=8 → `q0=[A,B,C,D], q1=[E,F,G], q2=[H, ALL]` (8-1 redistribution)
     - N=10 → `q0=4, q1=4, q2=[I, J, ALL]`
     - N=15 → `q0=4, q1=4, q2=4, q3=[M, N, O, ALL]` (round max)
     (ALL = `[queue.select_all_known]` option)
   - Each word-option: `{label:"<word>", description:"<lang> · <hint>"}`
   - question text: `[queue.question]` — same on every question. header: `Voca queue` (truncate per-page if needed).
4. **Hand off to subagent.** Resolve the user's primary language **before** building the subagent prompt: `PRIMARY=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh primary_lang_name)`. Substitute that string into the `{{PRIMARY}}` placeholder when synthesizing the prompt below. Spawn a `general-purpose` Agent with the resulting prompt. The subagent receives the selections + round payload and processes:

   ```
   You are processing the result of a /voca queue picker round. The user has already chosen — do NOT call AskUserQuestion or the picker again.

   Inputs:
     ACCEPTED (objects with word/lang/hint):  <JSON array>
     REJECTED_KNEW (rejected via page-wide "select all known" option): <JSON array of strings>
     REJECTED_SKIP (simply unselected): <JSON array of strings>

   For EACH accepted word:
     - Infer meaning (1 line, in {{PRIMARY}}), example (1 sentence, source language), context (1-2 lines from recent conversation excerpt — generic technical context if unknown), domain (subset of `${CLAUDE_PLUGIN_ROOT}/scripts/domains.txt`), source (closest single tag from `${CLAUDE_PLUGIN_ROOT}/scripts/sources.txt`).
     - Build JSON `{"word":"...","lang":"...","meaning":"...","example":"...","context":"...","source":"...","domain":[...],"added_via":"auto-hook"}` and pipe to `bash ${CLAUDE_PLUGIN_ROOT}/scripts/add.sh`. Capture the printed accepted-words plus resolved tags.

   Logging — append rows to `${CLAUDE_PLUGIN_DATA}/voca-candidates-log.tsv` (8 cols, tab-separated, ISO 8601 UTC `extracted_at`):
     - accepted:        `<word>\t<now>\t1\t\tvoca-add\t0\t<lang>\t`
     - rejected_knew:   `<word>\t<now>\t0\tuser marked as already known via picker\tvoca-add\t0\t<lang>\t`
     - rejected_skip:   `<word>\t<now>\t0\tuser skipped via /voca queue UI\tvoca-add\t0\t<lang>\t`

   Cleanup: remove ALL words from this round (≤15) from `${CLAUDE_PLUGIN_DATA}/voca-candidates.json` `pending` (regardless of accept/reject):
     jq --argjson words '<JSON array of all round words, lowercased>' '.pending |= map(select(([.word | ascii_downcase] | inside($words)) | not))' ${CLAUDE_PLUGIN_DATA}/voca-candidates.json > tmp && mv tmp ${CLAUDE_PLUGIN_DATA}/voca-candidates.json

   Reply with EXACTLY ONE LINE in this format (omit empty groups):
     `Accepted: A (tag1,tag2), B. Rejected (knew): X, Y. Rejected (skip): Z. Queue: N remaining.`
   ```

   Subagent responsibilities:
   - For each accepted word-option: run **Add workflow** with `added_via:"auto-hook"`, tags inferred from hint+context.
   - For each unselected word-option: append a row to `voca-candidates-log.tsv` with `accepted=0`, `command_used="voca-add"`, and `rejected_reason`:
     - if the user selected the `[queue.select_all_known]` option (on the last question's last slot) → `"user marked as already known via picker"` for **all unselected words across all questions in this round** (not just the last question — the option is page-wide)
     - otherwise → `"user skipped via /voca queue UI"`
   - Remove all round candidates (≤15, regardless of selection) from `voca-candidates.json`.
   - Reply 1 line. Split rejected into knew vs skip when both exist: `Accepted: A (tag1,tag2), B. Rejected (knew): C, D. Rejected (skip): E. Queue: N remaining.` Omit the empty groups.
5. **Main context** passes the subagent's 1-line reply through verbatim. If `remaining_unshown > 0` (from step 1), ask in plain text: `[queue.continue]` (no GUI).

### Scan workflow (invoked by `/voca scan`, `/voca queue` when empty, or by natural language "collect words from this session" / "이 세션 단어 모아줘")

**Async-only.** The previous in-context default path is removed — scanning the user's main conversation in-line polluted the working context. All scans now run in a separate process via `voca-extract-async.sh` (Haiku via `claude -p`) and dedup against `voca.tsv` automatically.

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan-launch.sh` and pass its stdout through verbatim. The script handles all branching internally:
- If `${CLAUDE_PLUGIN_DATA}/.voca-extract.lock.d` exists and was created < 120s ago → prints `[scan.already_running]` and skips spawning.
- Otherwise → resolves the latest transcript jsonl, spawns `voca-extract-async.sh` in the background, prints `[scan.spawned]`, and (if the queue already has pending entries) appends `[scan.status_queue]` with the count.

The async hook (`voca-extract-async.sh`) filters candidates against the full `voca.tsv` at extraction time. A second dedup pass runs at queue display time (step 3) to catch words added between extraction and display.

#### Scan status (`/voca scan --status`)

Check extractor state and report queue size:

```bash
# Running?
if [[ -d "${CLAUDE_PLUGIN_DATA}/.voca-extract.lock.d" ]]; then
  STATUS="[scan.status_running]"
else
  STATUS="[scan.status_idle]"
fi
# Last activity
LAST=$(tail -1 "${CLAUDE_PLUGIN_DATA}/voca-hook.log" 2>/dev/null || echo "(no log)")
# Queue size
PENDING=$(jq '.pending | length' "${CLAUDE_PLUGIN_DATA}/voca-candidates.json" 2>/dev/null || echo 0)
```

Reply: `$STATUS` + last activity line + `[scan.status_queue]` with `$PENDING`.

### Clear queue (natural language — "clear the queue" / "큐 비워줘")

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/queue-clear.sh` and pass through its 1-line confirmation. There is no slash subcommand for this; rely on natural-language intent.

### Accept/reject in conversation (natural-language fallback)

If the user reacts to the picker without re-running `/voca queue` (e.g., names extra words to add or reject in plain text), route the same way: Add workflow for accepted, log + queue removal for rejected.

### Search (`/voca search <query>`)

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/search.sh "$query"` — case-insensitive grep across word/meaning/example/context. Pass through.

### Stats (`/voca stats`)

`bash ${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh` — at-a-glance dashboard. Pass through verbatim. Output starts with the **Vocabulary level** block (en/ja/ko estimated size + CEFR band + tested-at + `+N since`), then lifecycle/rating counts, daily activity sparklines (added/mastered/archived for last 7d), velocity & streaks, time-to-master, top domains/sources/lang, hook precision/latency/via/commands/reject reasons, top by seen_count, stale active words.

### Setup workflow (`/voca setup` — first-run only)

One-time onboarding wizard. Skips the Prerequisites guard (this is the only workflow exempt from it).

**UI language rule:** For Steps 1–2, use `UI_LANG=en` — the user's primary language is unknown. This applies to **all output**: AskUserQuestion text, narration, and status messages. From Step 3 onward (after primary is set), switch `UI_LANG` to the newly set primary language.

1. **Check if already done**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-guard.sh forbid`. If the script prints anything, pass it through verbatim and stop.

2. **Step 1 — Language selection** (multiSelect AskUserQuestion):
   - question: `[setup.lang_question]` · header: `"Voca setup"`
   - options: `[{label:"[lang.ko]", description:"[lang.ko_desc]"}, {label:"[lang.ja]", description:"[lang.ja_desc]"}, {label:"[lang.en]", description:"[lang.en_desc]"}]`
   - For each language **not** selected, persist `{"spoken": false}`:
     ```bash
     echo '{"spoken": false}' | bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh write_lang <lang>
     ```

3. **Step 2 — Primary language** (controls `meaning` / `hint` output):
   - If exactly **1** language was selected → auto-set: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/profile-set-primary.sh <code>`.
   - If **2+** languages were selected → AskUserQuestion (single-select), question `[setup.primary_question]`, header `"Primary lang"`, options drawn from the selected set (label format `[lang.ko] (ko)` / `[lang.en] (en)` / `[lang.ja] (ja)`). On response, run `profile-set-primary.sh <code>`.

4. **Step 3 — Scan model** (single-select AskUserQuestion):
   - question: `[setup.scan_model_question]` · header: `"Scan model"`
   - options: `[{label:"haiku", description:"Fast & cheap (Recommended)"}, {label:"sonnet", description:"3× cost, better accuracy"}, {label:"opus", description:"5× cost, best accuracy"}]`
   - On response: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set scan.model <selection>`

5. **Step 4 — Level test**: For each selected language, run **Test Flow** (below) sequentially (en → ja → ko order).

6. **Step 5 — Complete**: Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh first_run_complete`, then `bash ${CLAUDE_PLUGIN_ROOT}/scripts/level-show.sh`. Pass output through verbatim. Reply `[setup.complete]`.

### Vocabulary level (`/voca level`, `/voca level test [lang]`, `/voca level reset [lang|all]`)

Vocabulary-size estimation modeled on testyourvocab.com / Preply: log-spaced frequency-rank probes + midpoint formula. Profile lives in `${CLAUDE_PLUGIN_DATA}/voca-profile.json`. Supported languages: `en`, `ja`, `ko`. Probe wordlists are bundled at `${CLAUDE_PLUGIN_ROOT}/scripts/wordlists/{en,ja,ko}.probes.tsv` (curated subset of hermitdave/FrequencyWords, CC-BY-SA 4.0).

Routing inside the skill:

- `/voca level` (profile present) → fast-path `level-show.sh` (handled by `voca.md`).
- `/voca level test [lang]` → **Test Flow** for the named language (or ask via AskUserQuestion if omitted).
- `/voca level reset [lang|all]` → fast-path `level-reset.sh`.

#### Test Flow (one language)

Given `$LANG` ∈ {en, ja, ko}:

**Stage 1 — coarse band (32 probes, 2 AskUserQuestion rounds)**

1. `STAGE1_JSON=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/level-probes.sh --lang "$LANG" --stage stage1)` — returns `{lang, stage, probes:[{rank,word}, ...]}` with 32 probes log-spaced over rank 50–30000, mastered/memorized words excluded.
2. **Build option blobs mechanically — never transcribe by hand.** Pipe the probe JSON straight to `level-options.sh`:
   ```bash
   printf '%s' "$STAGE1_JSON" | bash ${CLAUDE_PLUGIN_ROOT}/scripts/level-options.sh - > /tmp/auq_stage1.json
   ```
   This produces a `[{round, questions:[{question, header, multiSelect, options:[{label,description}]}, ...]}, ...]` array, one entry per round. Use the `questions` array of round 1 for the first AskUserQuestion call, round 2 for the second. **Do not retype labels** — copy the `options` array from the file as-is, or pipe to `jq` to extract the round's `questions` block directly into the AskUserQuestion payload. Hangul syllables differ by codepoint (e.g., U+C26C `쉬` vs U+C270 `쉰`), and a single mistyped character produces non-existent words like `쉰엄쉰엄` from `쉬엄쉬엄`.

3. **Verify before invoking** AskUserQuestion. Save the assembled questions array to a file and run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/level-options-verify.sh /tmp/probes_stage1.json /tmp/auq_payload.json
   ```
   Exit 0 = every label round-trips to the probe JSON. Exit 1 = a stray label was introduced; STOP and rebuild from `level-options.sh` rather than calling AskUserQuestion. (The verifier accepts the full `[{round,questions}]` array, a bare `questions` array, or a single `{questions}` object.)
4. Collect known/unknown for all 32 probes. Build `STAGE1_RESULTS` JSON:
   ```json
   {"lang":"en","stage":"stage1","results":[{"rank":50,"known":true},{"rank":64,"known":false}, ...32 entries]}
   ```
4. Pipe to `level-record.sh`. Capture stdout — it prints e.g. `Stage 1 (EN): ~4,740 추정. Stage 2 band [1184, 18944] 진행.` Display this single line, then move on.
5. Re-read the band from profile: `BMIN=$(bash lib-profile.sh lang en | jq '.stage2_band[0]')`, `BMAX=...[1]`.

**Stage 2 — narrow band (64 probes, 4 AskUserQuestion rounds)**

1. `STAGE2_JSON=$(bash level-probes.sh --lang $LANG --stage stage2 --band-min $BMIN --band-max $BMAX --exclude-words "<comma-list>")` — up to 64 probes within band, **excluding every Stage 1 word**. Build the comma-list from the Stage 1 probe JSON: `EXCL=$(printf '%s' "$STAGE1_JSON" | jq -r '.probes | map(.word) | join(",")')`. Failing to pass `--exclude-words` causes Stage 1 words inside the Stage 2 band to re-appear in the picker (e.g. KO band [6926, 50000] re-surfaces 사또/외팔이/막일/괴질/...).
2. Build option blobs via `level-options.sh` (same as Stage 1) and run **up to 4 rounds** of AskUserQuestion (16 word-slots each, 4q × 4opts). Verify each round's payload with `level-options-verify.sh` before invoking. If pool < 64, the final round may have fewer slots — let `multiSelect:true` work with whatever's there.
3. Build COMBINED results = Stage1 results + Stage2 results (96 entries when full pool):
   ```json
   {"lang":"en","stage":"stage2","results":[...96 {rank,known} objects]}
   ```
4. Pipe to `level-record.sh`. Pass its confirmation through verbatim. Below the 17000 native gate it prints **one** line (CEFR only): `EN 추정 어휘 7,930 (B2 — Upper-intermediate). 96 probes, 69 known.`. At/above 17000 it prints **two** lines (CEFR + native distribution reference): `EN 추정 어휘 22,500 (Native — Educated adult). 96 probes, 80 known. \n Native 분포 참고: 평균 native (성인) | testyourvocab.com 2013 (2M+ samples).`.
5. **Stage 3 trigger check** — `level-record.sh` sets `.stage3_recommended` and prints `Stage 3 권장 …` on a separate line **only if** the user saturated Stage 1+2 (≥90% known AND midpoint within 5000 of probed max). When that line appears, immediately proceed to Stage 3 below; otherwise the test is complete.

**Stage 3 — rare-band refinement (32 probes, 2 AskUserQuestion rounds)** — supported for KO, JA, EN. Each language ships its own `<lang>.rare.tsv`: ko (ko_full + kowiki titles, ceiling 45k), ja (BCCWJ, ceiling 50k, katakana loanwords excluded), en (en_50k + enwiki titles, ceiling 60k). All rare lists start at rank 20000.

1. Build the cumulative exclusion list = every Stage 1 + Stage 2 word: `EXCL3=$(printf '%s' "$STAGE1_JSON" "$STAGE2_JSON" | jq -rs '[.[] | .probes[].word] | join(",")')`. Then `STAGE3_JSON=$(bash level-probes.sh --lang $LANG --stage stage3 --exclude-words "$EXCL3")` — 32 probes from `<lang>.rare.tsv` (rank 20000+) excluding everything already shown.
2. Build option blobs via `level-options.sh` and run **2 rounds** of AskUserQuestion (16 word-slots each, 4q × 4opts). Verify each round's payload with `level-options-verify.sh` before invoking — labels MUST round-trip to the probe JSON byte-for-byte.
3. Build COMBINED results = Stage1 + Stage2 + Stage3 (128 entries when full pool):
   ```json
   {"lang":"ko","stage":"stage3","results":[...128 {rank,known} objects]}
   ```
4. Pipe to `level-record.sh`. The `stage3` mode overrides the Stage 2 final fields with the broader-pool estimate. Stage 3 estimates are by definition ≥17000, so the output is always **two lines** — CEFR/native band on the first, `Native 분포 참고: …` on the second. Pass both lines through verbatim (e.g. `KO 추정 어휘 38,400 (Native — Top tier). 128 probes, 124 known. \n Native 분포 참고: 상위 3% (전문 직군 / 작가) | 김광해 2003 / 국립국어원 빈도조사 (±10%).` / `JA 추정 어휘 47,200 (Native — Top tier). 128 probes, 119 known. \n Native 분포 참고: 高校卒 ~ 大学生 | NTT 語彙数推定テスト 補正版.`).

**Style for the test rounds:**

- Don't narrate "Round 1 starting" / "Submitting results" between AskUserQuestion calls. Just call them.
- Don't echo the probe JSON, the results JSON, or the per-word lists.
- Final reply per language is the single `level-record.sh` confirmation line (Stage 2 line if no Stage 3, Stage 3 line if Stage 3 ran).
- If the user explicitly aborts mid-test (e.g. closes the picker, sends "그만" / "stop"), stop without writing partial results.

#### `/voca level test [lang]` (re-test)

If `lang` is omitted, ask once via AskUserQuestion (single-select, options `[en, ja, ko]`). Then run the Test Flow above for that language. The existing `tested_at`, `history`, and `memorized_baseline` are overwritten on Stage 2 finalization (history is appended, not replaced).

#### `/voca level reset [lang|all]`

Fast-path; not handled in this skill. The router runs `bash ${CLAUDE_PLUGIN_ROOT}/scripts/level-reset.sh --lang <arg>` and passes the 1-line confirmation through.

### Config UI (`/voca config` — no args, interactive AskUserQuestion menu)

When `/voca config` is invoked with NO arguments, drive the UI inline from main session. (Args path — `config show|get|set|reset` — is fast-path via `config.sh` and handled by the dispatcher.)

**Stage 1 — section picker** (1 question, 4 options, single-select):

```
question: [config.section_question]
header:   "Voca config"
options:
  - {label: [config.list_columns],       description: [config.list_columns_desc]}
  - {label: [config.list_options],        description: [config.list_options_desc]}
  - {label: [config.picker_scan],         description: [config.picker_scan_desc]}
  - {label: [config.primary_optimize],    description: [config.primary_optimize_desc]}
```

**Stage 2 — branch on selection**:

**(a) [config.list_columns]** — 3 questions, multiSelect, 4 options each (12 columns total).
- Before issuing: read current selection via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh get list.columns`. For each option that is **already selected**, append `[config.current_marker]` to its `label`. Unselected options get no marker. (The pre-checked-state API doesn't exist on AskUserQuestion, so the label suffix is the closest visual hint.)
- Questions (titles unique — suffix `(1/3)` etc.):
  - Q1 (multi): `word`, `lang`, `meaning`, `source`
  - Q2 (multi): `domain`, `seen`, `age`, `via`
  - Q3 (multi): `status`, `rating`, `example`, `context`
- On response: union of selected labels → JSON array → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.columns '<JSON>'`.
- Reply 1 line: `Saved list.columns: word,lang,meaning,seen,age,via,status.`

**(b) [config.list_options]** — 4 questions, single-select:
- Before issuing: read current values once via `CFG=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh show)` and extract `list.default_n`, `list.default_status`, `list.sort`, `list.widths.meaning` (jq paths). For each question, append `[config.current_marker]` to the option label that matches the current value.
- Q1: default N → `["10","20","50","100"]` (Other = free integer)
- Q2: default status → `["active","mastered","archived","all"]`
- Q3: sort → `["last_seen desc","seen_count desc","first_seen desc","word asc"]`
- Q4: meaning width → `["20","30","40","50"]` (Other = free)
- Per response:
  - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.default_n <N>`
  - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.default_status <status>`
  - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.sort "<sort>"` (quoted — has space)
  - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.widths.meaning <W>`
  - Auto-sync domain width: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.widths.domain $((W - 5))` (≥10 floor).
- Reply 1 line listing saved keys.

**(c) [config.picker_scan]** — 3 questions, single-select:
- Before issuing: read current values once via `CFG=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh show)` and extract `picker.max_per_round`, `scan.model`, `scan.dedup_log_knew`. For each question, append `[config.current_marker]` to the option label that matches the current value.
- Q1: picker max_per_round → `["5","10","15"]`
- Q2: scan model → `["haiku","sonnet","opus"]`
  - haiku: fast & cheap — default. General use.
  - sonnet: higher quality, ~3× cost.
  - opus: most accurate jargon/technical extraction, ~5× cost. Stop hook runs every session — watch usage.
- Q3: scan dedup_log_knew → `["true","false"]` (label `on (true)` / `off (false)`)
- Per response: `config.sh set picker.max_per_round <N>` / `config.sh set scan.model <model>` / `config.sh set scan.dedup_log_knew <bool>`.
- Reply 1 line listing saved keys.

**(d/e) [config.primary_optimize]** — sub-picker first.

When this option is selected, ask one more AskUserQuestion to disambiguate:

```
question: [config.sub_question]
header:   "Sub-pick"
options:
  - {label: [config.primary_change],       description: [config.primary_change_desc] (fill %s with current primary name)}
  - {label: [config.optimize_recommend],   description: [config.optimize_recommend_desc]}
```

Before issuing, fill `<PRIMARY_NAME>` with the result of `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh primary_lang_name` so the user sees the current value. Branch to **(e)** or **(d)** based on selection.

**(e) [config.primary_change]** — 1 question, single-select.

1. Read spoken languages: `SPOKEN=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh read | jq -r '(.languages // {}) | to_entries | map(select(.value.spoken == true)) | map(.key) | join(",")')`. If empty, reply 1 line: `[config.primary_no_profile]` and exit.
2. Read current primary: `CURRENT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/lib-profile.sh primary_lang)`.
3. Build options dynamically — only include languages that appear in `$SPOKEN`. Label format: `[lang.ko] (ko)` / `[lang.en] (en)` / `[lang.ja] (ja)`. If a language equals `$CURRENT`, append `[config.current_marker]` to the label.
4. AskUserQuestion:
   ```
   question: [setup.primary_question]
   header:   "Primary lang"
   options:  <built above; 1-3 entries>
   ```
5. On response, extract the language code (`ko`/`en`/`ja`) from the label and run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/profile-set-primary.sh <code>`. Pass the 1-line confirmation through verbatim.
6. The new primary takes effect on the **next** `/voca add`, scan, and queue picker — existing TSV rows are not retranslated.

**(d) [config.optimize_recommend]** — 2-turn flow.

**Turn 1** (Optimize selected) — no AskUserQuestion. Reply in plain text using `[optimize.instruction]`.

End the turn here. (If the user names a width number directly, jump to fallback B in Turn 2.)

**Turn 2** (screenshot or width received):

1. **Estimate**:
   - Use vision: monospace cell width (px) ÷ terminal body px → char count. Or read where wrap occurs.
   - Ambiguous → **fallback A**: AskUserQuestion `[terminal.width_question]` opts `["80","100","120","140"]` (Other = integer).
   - User stated number directly → **fallback B**: use as-is.
2. **Compute**: `OUT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/optimize.sh <AVAIL>)`. Paste stdout (JSON line + preview) into reply as a fenced code block. Also capture for use as `preview` content below:
   - `PREVIEW_APPLY` = the post-blank-line portion of `OUT` (header row at recommended width + the `(N/AVAIL cols, dropped: …)` line). Multi-line monospace.
   - `PREVIEW_WIDEN` = a 2-3 line text summary describing the widen delta, e.g. `meaning_w: <MW> → <MW+6>\ndomain_w:  <DW> → <DW+6>\n(columns unchanged; total may exceed available)`.
   - `PREVIEW_NARROW` = mirror of above with `−6` and clamp note (`MW≥12, DW≥10`).
   - `PREVIEW_CANCEL` = single line, e.g. `(no changes — current settings preserved)`.
3. **Confirm UI** — single AskUserQuestion, header `Voca opt`. Each option carries a `preview` so the user sees the consequence side-by-side before clicking:
   ```
   question: [optimize.confirm] (fill %d with <AVAIL>)
   options:
     - {label: [optimize.apply],    description: [optimize.apply_desc],  preview: <PREVIEW_APPLY>}
     - {label: [optimize.widen],    description: [optimize.widen_desc],  preview: <PREVIEW_WIDEN>}
     - {label: [optimize.narrow],   description: [optimize.narrow_desc], preview: <PREVIEW_NARROW>}
     - {label: [optimize.cancel],   description: [optimize.cancel_desc], preview: <PREVIEW_CANCEL>}
   ```
4. **Apply**:
   - `[optimize.apply]`: extract `columns` / `meaning_w` / `domain_w` from JSON →
     ```
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.columns '<COLS_JSON>'
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.widths.meaning <MW>
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh set list.widths.domain  <DW>
     ```
   - `[optimize.widen]` / `[optimize.narrow]`: `MW±6` (clamp 12–60), `DW=MW−5` (≥10), columns unchanged, run the same 3 sets.
   - `[optimize.cancel]`: 1-line abort `[optimize.cancelled]`
5. Reply 1 line: `Saved list.columns(N), meaning=W, domain=W-5.`

**No looping**: each `/voca config` invocation handles one section. User reinvokes `/voca config` for the next change.

### Reclassify (`/voca reclassify [--all|--pending|<word>] [--dry-run]`)

Re-infer the `domain` (multi-select) for existing rows using current `domains.txt` options. Useful after adding new categories (e.g. ai/backend/frontend) so legacy rows benefit.

1. **Target selection**:
   - `--pending` (default): `awk -F'\t' 'NR>1 && ($7=="" || $7=="[]" || $7=="[\"misc\"]") {print $1}' ${CLAUDE_PLUGIN_DATA}/voca.tsv`
   - `--all`: every row
   - `<word>`: single row (use `find_word`)
2. **Scale guard**: if target count > 20, ask user once `[reclassify.confirm]` (fill %d with count) before continuing.
3. **Per row**: read word + meaning + example + context (`awk -F'\t' -v w="$word" 'tolower($1)==tolower(w) {print $1"\t"$3"\t"$4"\t"$5}' voca.tsv`). Pick 1-3 most fitting options from `domains.txt` (run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/domain-list.sh` to read the registry).
4. **Mode**:
   - `--dry-run`: print `word | old_domain → new_domain` table, no writes.
   - default: for each changed row, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/set-domain.sh "$word" '<json_array>'`. End with 1-line summary: `Reclassified N words (M unchanged).`
5. **Style**: don't echo per-row JSON; pass each `set-domain.sh` 1-line confirmation through verbatim.

## TSV cheat sheet

`voca.tsv` columns (1-indexed, tab-separated):

| # | name | values |
| --- | --- | --- |
| 1 | `word` | string |
| 2 | `lang` | en / ja / ko / mixed / other |
| 3 | `meaning` | 1-line definition in user's primary language (default Korean; change via `/voca config` → primary lang) |
| 4 | `example` | 1-line example in source language |
| 5 | `context` | 1-2 line conversation excerpt |
| 6 | `source` | one of `sources.txt` (or empty) |
| 7 | `domain` | JSON array of `domains.txt` names (e.g. `["ai","backend","software"]`). Current options: software/infra/medical/business/science/finance/language/culture/misc + ai/backend/frontend/devops/security/data/mobile |
| 8 | `seen_count` | int ≥ 1 |
| 9 | `first_seen_at` | ISO 8601 date |
| 10 | `last_seen_at` | ISO 8601 date |
| 11 | `added_via` | auto-hook / manual / review / import |
| 12 | `user_rating` | memorized / learning / unsure / (empty) |
| 13 | `status` | active (default) / mastered / archived |
| 14 | `user_note` | free text (no tabs/newlines) |
| 15 | `mastered_at` | ISO 8601 date — set when status transitions to mastered (via rate memorized or master.sh); cleared by restore |
| 16 | `archived_at` | ISO 8601 date — set when archived; cleared by restore |

Auto-promote: `user_rating=memorized` ⇒ `status=mastered` + `mastered_at=today` (handled by `rate.sh`).
Header auto-upgrade: `lib.sh` rewrites the header in place if the file exists with an older column count, so manual migration is unnecessary.

`voca-candidates-log.tsv` columns:

| # | name | values |
| --- | --- | --- |
| 1 | `candidate` | string |
| 2 | `extracted_at` | ISO 8601 datetime |
| 3 | `accepted` | `1` / `0` / `` |
| 4 | `rejected_reason` | free text |
| 5 | `command_used` | voca-add / voca-list / voca-review / voca-rate / auto / none |
| 6 | `hook_latency_ms` | int |
| 7 | `lang_guess` | en / ja / ko / mixed / other |
| 8 | `session_hint` | repo or topic hint |

`voca-profile.json` shape (vocabulary level):

```jsonc
{
  "spoken_count": 3,                  // sum of languages with spoken==true
  "first_run_completed_at": "...",    // ISO date, set when wizard finishes
  "first_run_declined": false,        // true = guard stops asking on /voca
  "languages": {
    "en": {
      "spoken": true,                 // wizard pick
      "estimated_size": 7930,         // testyourvocab-rounded vocab estimate
      "level_band": "B2 — Upper-intermediate",
      "tested_at": "2026-04-30",
      "stage1_rank": 4736,            // raw mid from Stage 1
      "stage2_band": [1184, 18944],   // [/4, x4] window, clamped to [50, 30000]
      "midpoint_rank": 7927,          // raw mid from final 96-probe pool
      "probes_total": 96,
      "probes_known": 69,
      "memorized_baseline": 0,        // count_memorized_for_lang at test time
      "history": [
        { "tested_at": "2026-04-30",
          "estimated_size": 7930,
          "probes_total": 96,
          "probes_known": 69 }
      ]
    },
    "ja": { "spoken": false }
  }
}
```

`level-show.sh` derives the displayed `(+N since)` counter at render time:
`current_memorized_for_lang - memorized_baseline` (floored at 0). `(stale)` is appended when `tested_at` is ≥ 90 days old.

## Style

- Replies should be short (1-3 lines unless the user asked for a list/table).
- **Reply rendering — non-negotiable.** Claude Code UI auto-collapses every Bash tool result to `… +N lines (ctrl+o to expand)`. Anything left only in the Bash result is **invisible** to the user. Therefore for every Bash call:
  - **Multi-line / table stdout** (`list.sh`, `search.sh`, `stats.sh`, `queue-show.sh`, `domain-list.sh`, `source-list.sh`, `level-show.sh`, `optimize.sh`, `config.sh show`) → paste the stdout **verbatim inside a fenced code block** in your reply.
  - **1-line confirmations** (`add.sh`, `rate.sh`, `archive.sh`, `master.sh`, `restore.sh`, `set-domain.sh`, `config.sh set`) → paste the line as plain text in your reply.
  - **Single self-check before ending the turn**: did I emit every Bash stdout in my reply? If not, paste it now. There is no exception.
- Do not wrap, paraphrase, summarize, trim columns, or add explanations to scripted output.
- For batch ops (queue picker accepts N words): one confirmation line per word + a 1-line summary. No progress narration.
- `meaning` is the only TSV field that follows the user's primary language (`/voca config` → primary lang; default Korean). `example`/`context`/`user_note` always stay in the source language.
- Never mention this skill or the scripts to the user — just do the work.
