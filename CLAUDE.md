# CLAUDE.md

Developer guide for Claude Code sessions working on the voca plugin.

## Project overview

Claude Code plugin for personal vocabulary tracking. Bash scripts + markdown skills + TSV data files. Supports en/ja/ko. Local-first, no external services.

## Directory structure

```
plugins/voca/
  .claude-plugin/plugin.json  -- plugin metadata (name, version, license)
  scripts/                    -- bash scripts (lib.sh, add.sh, list.sh, rate.sh, etc.)
    wordlists/                -- frequency-ranked probe word lists for level test (en/ja/ko)
  commands/                   -- slash command routing (.md files with frontmatter)
  skills/voca/SKILL.md        -- main skill: all workflows, UI strings, queue logic
  hooks/                      -- Stop hook for auto-extraction (voca-extract.sh)
  messages/                   -- i18n TSV files (ko.tsv, en.tsv, ja.tsv)
  data/                       -- seed files (domains.default.txt, sources.default.txt)
  tools/                      -- helper tools (_curate.py)
```

## Naming conventions

- Brand name is **voca** (NOT `vocab`)
- File names: kebab-case (e.g., `level-options.sh`, `domain-add.sh`)
- Shell variables: UPPER_SNAKE (e.g., `STATE_DIR`, `PLUGIN_ROOT`, `WORDS_TSV`)
- TSV column names: snake_case (e.g., `first_seen_at`, `user_rating`)

## lib.sh contract

Every script MUST source lib.sh first:
```bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
```

### Key variables provided
- `PLUGIN_ROOT` -- read-only plugin install dir (resolved from `CLAUDE_PLUGIN_ROOT`)
- `STATE_DIR` -- per-user writable dir (resolved: `VOCA_STATE_DIR` > `CLAUDE_PLUGIN_DATA` > `VOCAB_DB_DIR` > `~/.claude/state`)
- `WORDS_TSV` -- main word entries file
- `LOG_TSV` -- candidate log
- `QUEUE_PATH` -- pending candidates JSON
- `PROFILE_PATH`, `CONFIG_PATH` -- user profile and config
- `DOMAINS_TXT`, `SOURCES_TXT` -- tag registries
- `MESSAGES_DIR`, `WORDLISTS_DIR`, `SEEDS_DIR` -- read-only resource dirs

### Key functions provided
- `init_db_if_missing()` -- ensures TSV files + seed files exist, auto-upgrades headers
- `find_word(word)` -- case-insensitive lookup, prints matching TSV line
- `atomic_rewrite(file, awk_args...)` -- safe awk-based file mutation via temp file
- `lock_acquire()` / `lock_release()` -- mkdir-based mutex for concurrent writes
- `tsv_strip()` -- sanitize a TSV field (strip tabs, newlines, trailing whitespace)
- `today()` -- UTC date in YYYY-MM-DD

**NEVER hardcode paths like `~/.claude/state/` -- always use `STATE_DIR`.**

## i18n rules

- User-facing strings in bash scripts: use `t()` / `ti()` from `lib-i18n.sh` with keys from `messages/*.tsv`
- User-facing strings in SKILL.md `AskUserQuestion` blocks: use the UI Strings table in SKILL.md
- When adding a new message key: **MUST update all 3 TSV files** (`ko.tsv`, `en.tsv`, `ja.tsv`) simultaneously
- Never hardcode Korean (or any language) in scripts -- always use message keys
- Locale resolution: `VOCA_LOCALE` > `LANG`/`LC_ALL` > `en` (fallback)

## TSV schema

`voca.tsv` has 16 columns defined by `WORDS_HEADER` in `lib.sh`:
```
word  lang  meaning  example  context  source  domain  seen_count  first_seen_at  last_seen_at  added_via  user_rating  status  user_note  mastered_at  archived_at
```

When changing columns, update `WORDS_HEADER` in `lib.sh`.

## SKILL.md paths

In `SKILL.md`, use these variables for paths -- never hardcode:
- `${CLAUDE_PLUGIN_ROOT}/scripts/` -- for script invocations
- `${CLAUDE_PLUGIN_DATA}/` -- for user data files

## Commit messages

Conventional commits: `feat|fix|chore|docs(scope): message`

Examples:
- `feat(commands): add /voca search subcommand`
- `fix(i18n): add missing ja.tsv keys for queue picker`
- `chore(version): bump to 0.1.3`

## PR rules

- **i18n**: any new message key requires ko + en + ja translations in all 3 TSV files
- **New command**: needs `commands/<name>.md` + optional `scripts/<name>.sh` + SKILL.md workflow section
- **SKILL.md paths**: use `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}` -- never hardcode absolute paths
- **No hardcoded natural language in scripts**: all user-facing text goes through `t()`/`ti()`
