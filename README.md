# voca — Claude Code Plugin

Local-first vocabulary tracker with TestYourVocab-style level estimation for **English / Japanese / Korean**. Words live in a TSV file in your home directory, never leave your machine, and are surfaced via the `/voca` slash command in Claude Code.

> 한국어 README: [README.ko.md](./README.ko.md)

## Install

```text
/plugin marketplace add <git-url-of-this-repo>
/plugin install voca@flame91-voca-marketplace
```

## What you get

- `/voca add <word>` — record a word with meaning, example, context, tags
- `/voca list` / `/voca search <q>` / `/voca stats` — inspect your collection
- `/voca level test [en|ja|ko]` — three-stage adaptive vocabulary size estimate (Stage 1 + 2 + 3)
- `/voca queue` — picker UI for auto-extracted candidates from your sessions
- Stop hook auto-extracts candidate words from each session (runs Haiku in the background, dedups against your existing TSV)

> **Privacy note:** the Stop hook posts the latest assistant turn (or, when triggered manually with `full` mode, the entire transcript) to Anthropic's Haiku API via your local `claude` CLI to identify candidate words. This uses your own Anthropic credentials; nothing is sent to any third party. Disable the hook by removing it from `~/.claude/settings.json` after install if you prefer.

## Environment variables

| var | default | purpose |
|---|---|---|
| `VOCA_LOCALE` | system locale (`ko`/`en`/`ja`, fallback `en`) | UI message language for shell scripts |
| `VOCA_STATE_DIR` | `${CLAUDE_PLUGIN_DATA}` if set, else `~/.claude/state` | where vocab.tsv / profile / config live |
| `VOCA_BACKUPS` | unset | (legacy) reserved for future use |

## Migrating from legacy install

If you previously had `~/.claude/scripts/vocab/`, `~/.claude/skills/vocab/`, `~/.claude/commands/voca.md`, etc. set up by hand, your **state files** at `~/.claude/state/vocab*` can be migrated into the plugin's data dir:

```sh
bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-from-legacy.sh --dry-run
bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-from-legacy.sh
```

Legacy script/skill/command files in `~/.claude/` are **not** auto-removed — verify the plugin works first, then delete them manually.

## Dependencies

- `bash` 4+, `jq`, `awk`, `sed`, `column`, `python3` (for ms-precision timestamps in the hook)
- macOS / Linux / WSL

## Versioning

Current: 0.1.0 — initial public plugin release.

## Limitations (v1)

- Slash command and skill UI labels (AskUserQuestion) are Korean. Shell-script result lines are localized to `VOCA_LOCALE`. Full UI i18n (Skill prompts) is planned for v2.
- Wordlist updates require rebuilding via `tools/_curate.py` (separate Python venv with kiwipiepy for Korean lemmatization).

## License

CC BY-SA 4.0 — see [LICENSE](./LICENSE) and [NOTICE](./NOTICE) for upstream attribution.
