---
description: Personal vocabulary tracker — add, list, review, rate, level, domain, source, queue, archive, master, restore, search, stats, reclassify, config. Backed by local TSV at ~/.claude/state/vocab.tsv.
---

> ## ⚠ CRITICAL — REPLY RENDERING (read before responding)
>
> Claude Code UI auto-collapses every Bash tool result to `… +N lines (ctrl+o to expand)`. Anything left only in the Bash result is **invisible** to the user.
>
> **Therefore: every Bash call you make in this skill MUST have its stdout re-emitted in your assistant text reply.**
> - Multi-line / table stdout → paste **verbatim inside a fenced code block** in your reply.
> - 1-line confirmation → paste the line as plain text in your reply.
>
> **Self-check before ending the turn**: *did I emit every Bash stdout in my reply?* If not, paste it now. No exceptions.

Invoke the **vocab** skill at `~/.claude/skills/vocab/SKILL.md` for any inference, AskUserQuestion UI, or workflow detail. This file is the dispatcher only.

User input: `$ARGUMENTS`

---

## 0) First-run guard (before any subcommand)

Run `STATE=$(bash ~/.claude/scripts/vocab/lib-profile.sh first_run_state)`.

- `STATE == "pristine"` AND requested subcommand is **not** `level` / `level test` / `level reset` → call AskUserQuestion **once**:
  - q: `"처음 사용하시는군요. 간단한 어휘력 테스트(~6분)로 프로필을 만들까요?"` · header: `"Vocab setup"`
  - opts: `[{label:"지금 진행", desc:"EN/JA/KO 중 구사 가능한 언어 선택"}, {label:"나중에", desc:"건너뛰고 다음에도 안 묻기"}]`
- "지금 진행" → load SKILL.md → run **Setup Wizard** → return to step 1 with original `$ARGUMENTS`.
- "나중에" / Other → `bash ~/.claude/scripts/vocab/lib-profile.sh first_run_decline` → continue step 1.
- `STATE == "completed"` / `"declined"` → skip this guard.

## 1) Parse `$ARGUMENTS`

Split into subcommand + args. Empty → default to `list`.

## 2) Fast-path (script + paste stdout)

Run the script. **Then paste its stdout into your reply** per the rules at the top.

| subcommand | script | output kind |
|---|---|---|
| `list [N] [--status=...] [--lang=...]` | `list.sh "$@"`       | TABLE → code block |
| `search <q>`                     | `search.sh "$@"`          | TABLE → code block |
| `stats`                          | `stats.sh`                | TABLE → code block |
| `domain list`                    | `domain-list.sh`          | TABLE → code block |
| `source list`                    | `source-list.sh`          | TABLE → code block |
| `domain add` / `domain remove`   | `domain-add.sh` / `domain-remove.sh` `"$@"` | 1-line → plain |
| `source add` / `source remove`   | `source-add.sh`  / `source-remove.sh`  `"$@"` | 1-line → plain |
| `archive` / `master` / `restore` | `archive.sh` / `master.sh` / `restore.sh` `"$@"` | 1-line → plain |
| `rate`                           | `rate.sh "$@"`            | 1-line → plain |
| `level` (profile exists)         | `level-show.sh`           | TABLE → code block |
| `level reset [lang|all]`         | `level-reset.sh --lang <arg>` | 1-line → plain |
| `config show` / `get` / `set` / `reset` (with args) | `config.sh "$@"` | TABLE/1-line → paste |

## 3) Inference / UI paths — load SKILL.md, follow the matching section

For these, read `~/.claude/skills/vocab/SKILL.md` and execute the section listed:

| subcommand / intent | SKILL.md section |
|---|---|
| `add` (with or without args)              | "Add a word" |
| `review`                                  | "Review" |
| `queue` (no args)                         | "Queue" — hybrid (main runs picker, subagent processes; subagent prompt template inside) |
| `config` (no args)                        | "Config UI" — Stage 1 + Stage 2(a)(b)(c)(d) |
| `level` (no profile or all `spoken:false`) | "Setup Wizard" |
| `level test [lang]`                       | "Test Flow" |
| `reclassify [...]`                        | "Reclassify" |
| natural language "이 세션 단어 모아줘" / "지금까지 대화 다시 훑어줘" | "Scan workflow" |
| natural language "큐 비워줘"                | "Clear queue" |
| natural language reactions to picker       | "Accept/reject in conversation" |

## 4) Self-check before ending the turn

Before submitting your final reply, confirm:

- [ ] Every Bash multi-line stdout is in your reply text inside a fenced code block.
- [ ] Every 1-line confirmation script (`add.sh` / `rate.sh` / `archive.sh` / `set-domain.sh` / `config.sh set` / etc.) line is in your reply text.
- [ ] No "and the rest is in the tool result" — the user does not see Bash results.

If any box fails, paste the missing output now.
