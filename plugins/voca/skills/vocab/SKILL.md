---
name: vocab
description: Personal vocabulary tracker — adds, queries, rates words; manages tag options (domain/source); processes the Stop-hook candidate queue via interactive picker; scans the current session to backfill missed candidates. Backed by local TSV files. Use when the user says things like "이 단어 저장해줘", "방금 그 단어 모르겠어", "지금까지 추가한 단어 보여줘", "/voca add/list/review/rate/archive/master/restore/domain/source/queue", "단어장 보여줘", "infra 태그 추가해줘", "큐 비워줘", "MCP만 추가하고 나머지는 무시", "지금까지 대화 다시 훑어줘", "이 세션 단어 모아줘", or when the user explicitly asks to record a word, manage vocab tags, accept/reject candidates, or backfill candidates from the current conversation.
---

# Vocab Tracker

Local-first vocabulary collection backed by TSV files. No external services, no auth required.

## Storage

- `~/.claude/state/vocab.tsv` — main word entries (16 columns; see cheat sheet)
- `~/.claude/state/vocab-candidates-log.tsv` — Stop hook telemetry (8 columns)
- `~/.claude/state/vocab-candidates.json` — pending Stop-hook candidate queue (JSON)
- `~/.claude/scripts/vocab/domains.txt`, `sources.txt` — tag option registries (plain text, `name color` per line)

The user can edit `vocab.tsv` directly in VS Code/Numbers/Excel — keep the header row and 14 columns intact.

## Candidate queue

The Stop hook writes auto-detected candidates to `vocab-candidates.json` and surfaces them via additionalContext. Format:

```json
{ "pending": [ {"word": "ephemeral", "lang": "en", "hint": "...", "extracted_at": "...", "hook_latency_ms": 234} ] }
```

Hook also dedups against two sources before queuing:
1. **`vocab.tsv`** — any word already tracked (regardless of status or rating). User has already chosen to record it.
2. **`vocab-candidates-log.tsv` rows where `rejected_reason == "user marked as already known via picker"`** — words the user explicitly dismissed via the page-wide "이 페이지의 모든 단어를 알고 있음" option. These act as a virtual "already-known archive" so the user is never re-prompted for the same word they previously declared they know. (Plain `skip` rejections do NOT enter the skip-list — those may legitimately resurface later.)

## Workflows

> **All Notion-era MCP calls (`notion-search`, `notion-create-pages`, `notion-update-page`, `notion-update-data-source`, `notion-fetch`) are gone.** Every operation now runs through `bash ~/.claude/scripts/vocab/<x>.sh`. The slash-command (`voca.md`) auto-routes simple subcommands to scripts; the workflows below cover what to do for inference-heavy commands.

### Add a word (`/voca add <word>` or natural language)

1. Determine the word. If the user said "그 단어" / "방금 단어", check the candidate queue first; otherwise extract from their message.
1a. Resolve the user's primary language **once at the start** of the workflow:
    `PRIMARY=$(bash ~/.claude/scripts/vocab/lib-profile.sh primary_lang_name)` (returns e.g. `Korean (한국어)` / `English` / `Japanese (日本語)`; fallback `Korean (한국어)`). Use `$PRIMARY` for the `meaning` field below.
2. Infer fields from the conversation:
   - `lang`: en/ja/ko/mixed/other
   - `meaning`: 1 line, in `$PRIMARY` (the user's primary language)
   - `example`: 1 sentence, in original language
   - `context`: 1-2 line excerpt of the surrounding conversation
   - `domain`: subset of options listed in `domains.txt` (use `bash ~/.claude/scripts/vocab/domain-list.sh` if unsure)
   - `source`: closest single tag from `sources.txt`
   - `added_via`: `manual` / `auto-hook` (from queue) / `review`
3. Build a JSON object and pipe it to `add.sh`:
   ```bash
   echo '{"word":"ephemeral","lang":"en","meaning":"...","example":"...","context":"...","source":"language","domain":["language"],"added_via":"manual"}' \
     | bash ~/.claude/scripts/vocab/add.sh
   ```
   `add.sh` handles dedup automatically (case-insensitive). Duplicates increment `seen_count` and update `last_seen_at`.
4. If the word came from the candidate queue, also remove it from `vocab-candidates.json` (jq with `del(...)`) and append a row to `vocab-candidates-log.tsv` with `accepted=1`, `command_used=vocab-add`.
5. Reply with the 1-line confirmation that `add.sh` already printed (e.g., `Added "ephemeral" — 잠시 동안만 존재하는, 일시적인.`). **Do not echo the JSON or paraphrase the script output.**

### List recent (`/voca list [N] [--status=...] [--lang=...]`)

Handled by `voca.md` fast-path (`list.sh`). The script renders a table; pass it through verbatim.

- `--status` filter: `active` (default) / `mastered` / `archived` / `all`
- `--lang` filter: `en` / `ja` / `ko` / `mixed` / `other` / `all` (omitted = no filter, same as `all`). Default is the value of `list.default_lang` in `vocab-config.json` if set.

### Review (`/voca review`)

Use **AskUserQuestion** for clickable rating UI.

1. Fetch candidates: `awk -F'\t' 'NR>1 && ($13=="active" || $13=="") && ($12==""||$12=="learning"||$12=="unsure")' ~/.claude/state/vocab.tsv | sort -t$'\t' -k8,8nr | head -16` (sort by `seen_count` desc, take top 16).
2. Take **up to 4 words** at a time. Build one AskUserQuestion call with up to 4 questions, one per word:
   - `question`: `"<word>" — <meaning> — 외웠어?`
   - `header`: word truncated to 12 chars
   - `multiSelect`: false
   - `options`: `[{label:"memorized", description:"<example>"}, {label:"learning", description:"아직 학습 중"}, {label:"unsure", description:"패스"}]`
3. After submission, for each rated word: `bash ~/.claude/scripts/vocab/rate.sh <word> <rating>`.
4. If unrated words remain, ask `4개 더 평가하시겠어요?` (text, not GUI).

### Rate (`/voca rate <word> <memorized|learning|unsure> [note]`)

Just `bash ~/.claude/scripts/vocab/rate.sh "$word" "$rating" "$note"`. The script auto-promotes to `mastered` when the rating is `memorized`.

### Archive / Master / Restore

`bash ~/.claude/scripts/vocab/archive.sh "$word"` / `master.sh` / `restore.sh`. Pass through the 1-line confirmation.

### Manage tag options — `domain` / `source`

- list: `bash ~/.claude/scripts/vocab/domain-list.sh` (handled by fast-path)
- add: `bash ~/.claude/scripts/vocab/domain-add.sh <name> [color]`
- remove: `bash ~/.claude/scripts/vocab/domain-remove.sh <name>` (also strips the tag from any matching row in `vocab.tsv`)
- same pattern for `source`

Allowed colors: gray, brown, orange, yellow, green, blue, purple, pink, red, default.

### Queue — `/voca queue` (single entry point)

`/voca queue` is the only queue subcommand. It launches the **Candidates Picker UI** (AskUserQuestion). All previous sub-options (`accept`, `reject`, `candidates`, `scan`, `clear`) have been removed — selection happens interactively, and the rare destructive/additive operations are reachable via natural language.

> **Execution mode (hybrid)**: AskUserQuestion can only render its UI from the main session — a subagent cannot prompt the user. So `/voca queue` is split:
> - **Main context** runs steps 1–4 (read queue → dedup → mark `shown:true` → AskUserQuestion picker round). These are bash + a single AskUserQuestion call; no per-word inference here.
> - **A general-purpose subagent** runs steps 5–8 (per-accept inference + `add.sh`, per-reject log append, queue cleanup, 1-line summary). The subagent receives the selections + 15-word payload via its prompt and never calls AskUserQuestion.
>
> This isolates the heaviest token cost (per-word inference for `add`) from the main conversation while keeping the picker UI functional. `voca.md`'s routing in `~/.claude/commands/voca.md` carries the orchestration template.

**Flow:**

1. Read `~/.claude/state/vocab-candidates.json`.
2. **If `pending` is empty** → do NOT scan in-context. Spawn the async extractor on the parent session transcript and stop:
   - find latest transcript: `LATEST=$(ls -t ~/.claude/projects/-${PWD//\//-}/*.jsonl 2>/dev/null | head -1)` (fallback: search `~/.claude/projects/*/`)
   - `nohup bash ~/.claude/hooks/vocab-extract-async.sh "$LATEST" full >>~/.claude/state/vocab-hook.log 2>&1 &`
   - reply: `큐가 비어 추출을 시작했습니다 (~30-60s). 잠시 후 /voca queue 다시 실행.`
3. **Filter** `pending` to entries with `shown: false` (unshown only). If no unshown entries remain, reply `큐에 새 단어가 없습니다 (전체 큐: N개).` and stop. Rationale: the user does not want to be re-prompted for candidates they already saw and dismissed in a previous picker render.
4. **Picker** — Take **up to 15 unshown candidates** for this round (one AskUserQuestion call can pack max 4 questions × 4 options = 16 slots; one slot is reserved for the "모두 알고 있음" option). **Before** invoking AskUserQuestion, set `shown: true` on those entries and persist `vocab-candidates.json` immediately, so that even a dismiss-without-response "consumes" the show. Then build **one** AskUserQuestion call with multiple questions (`multiSelect: true` on each):
   - Distribute the N candidates into questions of up to 4 word-options each, in order. Append one extra option `이 페이지의 모든 단어를 알고 있음` (description: `체크 안 한 나머지 단어를 '이미 알고 있음'으로 reject 처리`) at the **end of the last question**.
   - **`minItems: 2` guard**: if the last question would end up with the "모두 알고 있음" option alone (1 option), pull one word from the previous question into the last one so each question has ≥ 2 options. Concretely:
     - N=1 → `q0=[A, 모두]`
     - N=3 → `q0=[A, B, C, 모두]`
     - N=4 → `q0=[A, B, C], q1=[D, 모두]` (4-1 redistribution)
     - N=7 → `q0=[A,B,C,D], q1=[E,F,G, 모두]`
     - N=8 → `q0=[A,B,C,D], q1=[E,F,G], q2=[H, 모두]` (8-1 redistribution)
     - N=10 → `q0=4, q1=4, q2=[I, J, 모두]`
     - N=15 → `q0=4, q1=4, q2=4, q3=[M, N, O, 모두]` (round max)
   - Each word-option: `{label:"<word>", description:"<lang> · <hint>"}`
   - question text: `추가할 단어를 골라주세요 (선택 안 한 항목은 reject로 처리됩니다).` — same on every question. header: `Vocab queue` (truncate per-page if needed).
5. **Hand off to subagent.** Resolve the user's primary language **before** building the subagent prompt: `PRIMARY=$(bash ~/.claude/scripts/vocab/lib-profile.sh primary_lang_name)`. Substitute that string into the `{{PRIMARY}}` placeholder when synthesizing the prompt below. Spawn a `general-purpose` Agent with the resulting prompt. The subagent receives the selections + 15-word payload and processes:

   ```
   You are processing the result of a /voca queue picker round. The user has already chosen — do NOT call AskUserQuestion or the picker again.

   Inputs:
     ACCEPTED (objects with word/lang/hint):  <JSON array>
     REJECTED_KNEW (rejected via "이미 알고 있음" page-wide option): <JSON array of strings>
     REJECTED_SKIP (simply unselected): <JSON array of strings>

   For EACH accepted word:
     - Infer meaning (1 line, in {{PRIMARY}}), example (1 sentence, source language), context (1-2 lines from recent conversation excerpt — generic technical context if unknown), domain (subset of `~/.claude/scripts/vocab/domains.txt`), source (closest single tag from `~/.claude/scripts/vocab/sources.txt`).
     - Build JSON `{"word":"...","lang":"...","meaning":"...","example":"...","context":"...","source":"...","domain":[...],"added_via":"auto-hook"}` and pipe to `bash ~/.claude/scripts/vocab/add.sh`. Capture the printed accepted-words plus resolved tags.

   Logging — append rows to `~/.claude/state/vocab-candidates-log.tsv` (8 cols, tab-separated, ISO 8601 UTC `extracted_at`):
     - accepted:        `<word>\t<now>\t1\t\tvocab-add\t0\t<lang>\t`
     - rejected_knew:   `<word>\t<now>\t0\tuser marked as already known via picker\tvocab-add\t0\t<lang>\t`
     - rejected_skip:   `<word>\t<now>\t0\tuser skipped via /voca queue UI\tvocab-add\t0\t<lang>\t`

   Cleanup: remove ALL 15 processed words from `~/.claude/state/vocab-candidates.json` `pending` (regardless of accept/reject):
     jq --argjson words '<JSON array of all 15 lowercased words>' '.pending |= map(select(([.word | ascii_downcase] | inside($words)) | not))' ~/.claude/state/vocab-candidates.json > tmp && mv tmp ~/.claude/state/vocab-candidates.json

   Reply with EXACTLY ONE LINE in this format (omit empty groups):
     `Accepted: A (tag1,tag2), B. Rejected (knew): X, Y. Rejected (skip): Z. Queue: N remaining.`
   ```

   Subagent responsibilities:
   - For each accepted word-option: run **Add workflow** with `added_via:"auto-hook"`, tags inferred from hint+context.
   - For each unselected word-option: append a row to `vocab-candidates-log.tsv` with `accepted=0`, `command_used="vocab-add"`, and `rejected_reason`:
     - if the user selected `이 페이지의 모든 단어를 알고 있음` (only on the last question's last slot) → `"user marked as already known via picker"` for the unselected words **on that last question**
     - otherwise → `"user skipped via /voca queue UI"`
   - Remove all 15 shown candidates (regardless of selection) from `vocab-candidates.json`.
   - Reply 1 line. Split rejected into knew vs skip when both exist: `Accepted: A (tag1,tag2), B. Rejected (knew): C, D. Rejected (skip): E. Queue: N remaining.` Omit the empty groups.
6. **Main context** passes the subagent's 1-line reply through verbatim. If more unshown candidates remain (i.e. N was capped at 15), ask in plain text: `남은 M개 더 처리할까요?` (no GUI).

### Scan workflow (invoked by `/voca queue` when empty, or by natural language "이 세션 단어 모아줘")

**Async-only.** The previous in-context default path is removed — scanning the user's main conversation in-line polluted the working context. All scans now run in a separate process via `vocab-extract-async.sh` (Haiku via `claude -p`) and dedup against `vocab.tsv` automatically.

```bash
LATEST=$(ls -t ~/.claude/projects/-${PWD//\//-}/*.jsonl 2>/dev/null | head -1)
# fallback if the project-encoded path produced no match:
[[ -z "$LATEST" ]] && LATEST=$(ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -1)
nohup bash ~/.claude/hooks/vocab-extract-async.sh "$LATEST" full >>~/.claude/state/vocab-hook.log 2>&1 &
```
Reply: `Spawned full-transcript extraction (~30-60s). /voca queue when ready.`

The async hook (`vocab-extract-async.sh`) already filters candidates against the full `vocab.tsv` regardless of status/rating, so no additional dedup is required here.

### Clear queue (natural language — "큐 비워줘")

Run `bash ~/.claude/scripts/vocab/queue-clear.sh` and pass through its 1-line confirmation. There is no slash subcommand for this; rely on natural-language intent.

### Accept/reject in conversation (natural-language fallback)

If the user reacts to the picker without re-running `/voca queue` (e.g., names extra words to add or reject in plain text), route the same way: Add workflow for accepted, log + queue removal for rejected.

### Search (`/voca search <query>`)

`bash ~/.claude/scripts/vocab/search.sh "$query"` — case-insensitive grep across word/meaning/example/context. Pass through.

### Stats (`/voca stats`)

`bash ~/.claude/scripts/vocab/stats.sh` — at-a-glance dashboard. Pass through verbatim. Output starts with the **Vocabulary level** block (en/ja/ko estimated size + CEFR band + tested-at + `+N since`), then lifecycle/rating counts, daily activity sparklines (added/mastered/archived for last 7d), velocity & streaks, time-to-master, top domains/sources/lang, hook precision/latency/via/commands/reject reasons, top by seen_count, stale active words.

### Vocabulary level (`/voca level`, `/voca level test [lang]`, `/voca level reset [lang|all]`)

Vocabulary-size estimation modeled on testyourvocab.com / Preply: log-spaced frequency-rank probes + midpoint formula. Profile lives in `~/.claude/state/vocab-profile.json`. Supported languages: `en`, `ja`, `ko`. Probe wordlists are bundled at `~/.claude/scripts/vocab/wordlists/{en,ja,ko}.probes.tsv` (curated subset of hermitdave/FrequencyWords, CC-BY-SA 4.0).

Routing inside the skill:

- `/voca level` (no profile yet, OR every language `spoken:false`) → **Setup Wizard** below.
- `/voca level` (profile present) → fast-path `level-show.sh` (handled by `voca.md`).
- `/voca level test [lang]` → **Test Flow** for the named language (or ask via AskUserQuestion if omitted).
- `/voca level reset [lang|all]` → fast-path `level-reset.sh`.

#### Setup Wizard

1. AskUserQuestion #1, **multiSelect: true**:
   - question: `"구사 가능한 언어를 선택하세요"` · header: `"Vocab setup"`
   - options: `[{label:"한국어", description:"ko 측정"}, {label:"일본어", description:"ja 측정"}, {label:"영어", description:"en 측정"}]`
2. For each language **not** selected, persist `{"spoken": false}`:
   ```bash
   echo '{"spoken": false}' | bash ~/.claude/scripts/vocab/lib-profile.sh write_lang <lang>
   ```
3. For each selected language, run **Test Flow** (below) sequentially (en → ja → ko order — keeps probe logic identical regardless of selection set).
4. **Set primary language** (controls `meaning` / `hint` output):
   - If exactly **1** language was selected → auto-set: `bash ~/.claude/scripts/vocab/profile-set-primary.sh <code>`.
   - If **2+** languages were selected → AskUserQuestion (single-select), question `"meaning을 어떤 언어로 받을까요?"`, header `"Primary lang"`, options drawn from the selected set (label format `한국어 (ko)` / `English (en)` / `日本語 (ja)`). On response, run `profile-set-primary.sh <code>`.
5. After primary is set, run `bash ~/.claude/scripts/vocab/lib-profile.sh first_run_complete` and then call `bash ~/.claude/scripts/vocab/level-show.sh` once. Pass its output through verbatim.

#### Test Flow (one language)

Given `$LANG` ∈ {en, ja, ko}:

**Stage 1 — coarse band (32 probes, 2 AskUserQuestion rounds)**

1. `STAGE1_JSON=$(bash ~/.claude/scripts/vocab/level-probes.sh --lang "$LANG" --stage stage1)` — returns `{lang, stage, probes:[{rank,word}, ...]}` with 32 probes log-spaced over rank 50–30000, mastered/memorized words excluded.
2. **Build option blobs mechanically — never transcribe by hand.** Pipe the probe JSON straight to `level-options.sh`:
   ```bash
   printf '%s' "$STAGE1_JSON" | bash ~/.claude/scripts/vocab/level-options.sh - > /tmp/auq_stage1.json
   ```
   This produces a `[{round, questions:[{question, header, multiSelect, options:[{label,description}]}, ...]}, ...]` array, one entry per round. Use the `questions` array of round 1 for the first AskUserQuestion call, round 2 for the second. **Do not retype labels** — copy the `options` array from the file as-is, or pipe to `jq` to extract the round's `questions` block directly into the AskUserQuestion payload. Hangul syllables differ by codepoint (e.g., U+C26C `쉬` vs U+C270 `쉰`), and a single mistyped character produces non-existent words like `쉰엄쉰엄` from `쉬엄쉬엄`.

3. **Verify before invoking** AskUserQuestion. Save the assembled questions array to a file and run:
   ```bash
   bash ~/.claude/scripts/vocab/level-options-verify.sh /tmp/probes_stage1.json /tmp/auq_payload.json
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

**Stage 3 — rare-band refinement (32 probes, 2 AskUserQuestion rounds)** — supported for KO, JA, EN. Each language ships its own `<lang>.rare.tsv`: ko (ko_full + kowiki titles, ceiling 45k), ja (BCCWJ, ceiling 50k), en (en_50k + enwiki titles, ceiling 60k).

1. Build the cumulative exclusion list = every Stage 1 + Stage 2 word: `EXCL3=$(printf '%s' "$STAGE1_JSON" "$STAGE2_JSON" | jq -rs '[.[] | .probes[].word] | join(",")')`. Then `STAGE3_JSON=$(bash level-probes.sh --lang $LANG --stage stage3 --exclude-words "$EXCL3")` — 32 probes from `<lang>.rare.tsv` (rank 15000+) excluding everything already shown.
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

Fast-path; not handled in this skill. The router runs `bash ~/.claude/scripts/vocab/level-reset.sh --lang <arg>` and passes the 1-line confirmation through.

### Config UI (`/voca config` — no args, interactive AskUserQuestion menu)

When `/voca config` is invoked with NO arguments, drive the UI inline from main session. (Args path — `config show|get|set|reset` — is fast-path via `config.sh` and handled by the dispatcher.)

**Stage 1 — section picker** (1 question, 4 options, single-select):

```
question: "어떤 설정을 조정할까요?"
header:   "Vocab config"
options:
  - {label: "List 컬럼 선택",   description: "/voca list에 표시할 컬럼"}
  - {label: "List 옵션",        description: "기본 N · 상태 필터 · 정렬 · meaning 너비"}
  - {label: "Picker / Scan",    description: "큐 picker 라운드 크기, 스캔 모델, dedup"}
  - {label: "주 언어 · Optimize", description: "meaning 출력 언어 변경 또는 컬럼·폭 자동 추천"}
```

**Stage 2 — branch on selection**:

**(a) "List 컬럼"** — 3 questions, multiSelect, 4 options each (12 columns total).
- Before issuing: read current selection via `bash ~/.claude/scripts/vocab/config.sh get list.columns`. For each option, append `[현재 ✓]` or `[현재 ✗]` to `description` so the user sees the delta.
- Questions (titles unique — suffix `(1/3)` etc.):
  - Q1 (multi): `word`, `lang`, `meaning`, `source`
  - Q2 (multi): `domain`, `seen`, `age`, `via`
  - Q3 (multi): `status`, `rating`, `example`, `context`
- On response: union of selected labels → JSON array → `bash ~/.claude/scripts/vocab/config.sh set list.columns '<JSON>'`.
- Reply 1 line: `Saved list.columns: word,lang,meaning,seen,age,via,status.`

**(b) "List 옵션"** — 4 questions, single-select:
- Q1: 기본 N → `["10","20","50","100"]` (Other = free integer)
- Q2: 기본 status → `["active","mastered","archived","all"]`
- Q3: 정렬 → `["last_seen desc","seen_count desc","first_seen desc","word asc"]`
- Q4: meaning 너비 → `["20","30","40","50"]` (Other = free)
- Per response:
  - `bash ~/.claude/scripts/vocab/config.sh set list.default_n <N>`
  - `bash ~/.claude/scripts/vocab/config.sh set list.default_status <status>`
  - `bash ~/.claude/scripts/vocab/config.sh set list.sort "<sort>"` (quoted — has space)
  - `bash ~/.claude/scripts/vocab/config.sh set list.widths.meaning <W>`
  - Auto-sync domain width: `bash ~/.claude/scripts/vocab/config.sh set list.widths.domain $((W - 5))` (≥10 floor).
- Reply 1 line listing saved keys.

**(c) "Picker / Scan"** — 3 questions, single-select:
- Q1: picker max_per_round → `["5","10","15"]`
- Q2: scan model → `["haiku","sonnet"]`
- Q3: scan dedup_log_knew → `["true","false"]` (label `켜기 (true)` / `끄기 (false)`)
- Per response: `config.sh set picker.max_per_round <N>` / `config.sh set scan.model <model>` / `config.sh set scan.dedup_log_knew <bool>`.
- Reply 1 line listing saved keys.

**(d/e) "주 언어 · Optimize"** — sub-picker first.

When this option is selected, ask one more AskUserQuestion to disambiguate:

```
question: "이 메뉴에서 무엇을 할까요?"
header:   "Sub-pick"
options:
  - {label: "주 언어 변경",        description: "meaning · hint 생성 언어 (현재: <PRIMARY_NAME>)"}
  - {label: "Optimize 자동 추천", description: "터미널 스크린샷으로 컬럼·폭 추천"}
```

Before issuing, fill `<PRIMARY_NAME>` with the result of `bash ~/.claude/scripts/vocab/lib-profile.sh primary_lang_name` so the user sees the current value. Branch to **(e)** or **(d)** based on selection.

**(e) "주 언어 변경"** — 1 question, single-select.

1. Read spoken languages: `SPOKEN=$(bash ~/.claude/scripts/vocab/lib-profile.sh read | jq -r '(.languages // {}) | to_entries | map(select(.value.spoken == true)) | map(.key) | join(",")')`. If empty, reply 1 line: `먼저 /voca level 로 언어 프로필을 만들어주세요.` and exit.
2. Read current primary: `CURRENT=$(bash ~/.claude/scripts/vocab/lib-profile.sh primary_lang)`.
3. Build options dynamically — only include languages that appear in `$SPOKEN`. Label format: `한국어 (ko)` / `English (en)` / `日本語 (ja)`. If a language equals `$CURRENT`, append ` [현재 ✓]` to the label.
4. AskUserQuestion:
   ```
   question: "meaning을 어떤 언어로 받을까요?"
   header:   "Primary lang"
   options:  <built above; 1-3 entries>
   ```
5. On response, extract the language code (`ko`/`en`/`ja`) from the label and run `bash ~/.claude/scripts/vocab/profile-set-primary.sh <code>`. Pass the 1-line confirmation through verbatim.
6. The new primary takes effect on the **next** `/voca add`, scan, and queue picker — existing TSV rows are not retranslated.

**(d) "Optimize"** — 2-turn flow.

**Turn 1** (Optimize selected) — no AskUserQuestion. Reply in plain Korean text:
> 터미널을 평소 사용하는 너비로 띄운 뒤, 빈 프롬프트 또는 `/voca list` 결과가 보이는 스크린샷을 다음 메시지에 첨부해주세요. 헤더가 어디서 끊기는지로 가용 너비를 추정합니다.

End the turn here. (If the user names a width number directly, jump to fallback B in Turn 2.)

**Turn 2** (screenshot or width received):

1. **Estimate**:
   - Use vision: monospace cell width (px) ÷ terminal body px → char count. Or read where wrap occurs.
   - Ambiguous → **fallback A**: AskUserQuestion `대략적 터미널 폭은?` opts `["80","100","120","140"]` (Other = integer).
   - User stated number directly → **fallback B**: use as-is.
2. **Compute**: `OUT=$(bash ~/.claude/scripts/vocab/optimize.sh <AVAIL>)`. Paste stdout (JSON line + preview) into reply as a fenced code block.
3. **Confirm UI** — single AskUserQuestion, header `Vocab opt`:
   ```
   question: "이 추천을 적용할까요? (<AVAIL>cols 가정)"
   options:
     - {label: "적용",          description: "위 columns/widths로 저장"}
     - {label: "meaning 폭 +6",  description: "한국어를 더 보고 싶을 때"}
     - {label: "meaning 폭 −6",  description: "여백을 더 두고 싶을 때"}
     - {label: "취소",          description: "변경하지 않고 종료"}
   ```
4. **Apply**:
   - `적용`: extract `columns` / `meaning_w` / `domain_w` from JSON →
     ```
     bash ~/.claude/scripts/vocab/config.sh set list.columns '<COLS_JSON>'
     bash ~/.claude/scripts/vocab/config.sh set list.widths.meaning <MW>
     bash ~/.claude/scripts/vocab/config.sh set list.widths.domain  <DW>
     ```
   - `+6` / `−6`: `MW±6` (clamp 12–60), `DW=MW−5` (≥10), columns unchanged, run the same 3 sets.
   - `취소`: 1-line abort `Optimize 취소.`
5. Reply 1 line: `Saved list.columns(N), meaning=W, domain=W-5. 다음 /voca list부터 반영.`

**No looping**: each `/voca config` invocation handles one section. User reinvokes `/voca config` for the next change.

### Reclassify (`/voca reclassify [--all|--pending|<word>] [--dry-run]`)

Re-infer the `domain` (multi-select) for existing rows using current `domains.txt` options. Useful after adding new categories (e.g. ai/backend/frontend) so legacy rows benefit.

1. **Target selection**:
   - `--pending` (default): `awk -F'\t' 'NR>1 && ($7=="" || $7=="[]" || $7=="[\"misc\"]") {print $1}' ~/.claude/state/vocab.tsv`
   - `--all`: every row
   - `<word>`: single row (use `find_word`)
2. **Scale guard**: if target count > 20, ask user once `N개 reclassify 진행할까요? (y/n)` before continuing.
3. **Per row**: read word + meaning + example + context (`awk -F'\t' -v w="$word" 'tolower($1)==tolower(w) {print $1"\t"$3"\t"$4"\t"$5}' vocab.tsv`). Pick 1-3 most fitting options from `domains.txt` (run `bash ~/.claude/scripts/vocab/domain-list.sh` to read the registry).
4. **Mode**:
   - `--dry-run`: print `word | old_domain → new_domain` table, no writes.
   - default: for each changed row, `bash ~/.claude/scripts/vocab/set-domain.sh "$word" '<json_array>'`. End with 1-line summary: `Reclassified N words (M unchanged).`
5. **Style**: don't echo per-row JSON; pass each `set-domain.sh` 1-line confirmation through verbatim.

## TSV cheat sheet

`vocab.tsv` columns (1-indexed, tab-separated):

| # | name | values |
| --- | --- | --- |
| 1 | `word` | string |
| 2 | `lang` | en / ja / ko / mixed / other |
| 3 | `meaning` | primary language 1줄 뜻 (기본 한국어; `/voca config` → "주 언어"로 변경) |
| 4 | `example` | 원어 예문 1줄 |
| 5 | `context` | 대화 발췌 1-2줄 |
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

`vocab-candidates-log.tsv` columns:

| # | name | values |
| --- | --- | --- |
| 1 | `candidate` | string |
| 2 | `extracted_at` | ISO 8601 datetime |
| 3 | `accepted` | `1` / `0` / `` |
| 4 | `rejected_reason` | free text |
| 5 | `command_used` | vocab-add / vocab-list / vocab-review / vocab-rate / auto / none |
| 6 | `hook_latency_ms` | int |
| 7 | `lang_guess` | en / ja / ko / mixed / other |
| 8 | `session_hint` | repo or topic hint |

`vocab-profile.json` shape (vocabulary level):

```jsonc
{
  "spoken_count": 3,                  // sum of languages with spoken==true
  "first_run_completed_at": "...",    // ISO date, set when wizard finishes
  "first_run_declined": false,        // true = guard stops asking on /vocab
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
- `meaning` is the only TSV field that follows the user's primary language (`/voca config` → "주 언어"; default 한국어). `example`/`context`/`user_note` always stay in the source language.
- Never mention this skill or the scripts to the user — just do the work.
