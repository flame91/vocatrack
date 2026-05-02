# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.6] - 2026-05-02

### Added
- Level assessment reference table in all READMEs: CEFR bands (A1–C2), native-speaker bands per language, source citations (testyourvocab.com, NTT語彙数推定テスト, 김광해 2003)
- Stage 3 smoothing guard: caps estimate within ±25% of Stage 2 to prevent rare-list noise from producing wild swings
- Systematic vocal exclamation filter (`JA_VOCAL_EXCL_PAT`): pattern-based `Xっ` detection + explicit block for Japanese wordlists

### Changed
- README header: `voca -- Claude Code Plugin` → `vocatrack` with centered logo
- `RARE_RANK_LO` raised from 15000 to 20000 across `_curate.py`, `level-probes.sh`, and `SKILL.md` to reduce Stage 2/3 overlap
- JA rare wordlist: all katakana loanwords blocked in rare mode, vocal exclamations removed (199 → 128 entries)
- KO rare wordlist: entries below rank 20000 removed (197 → 142 entries)
- EN rare wordlist: entries below rank 20000 removed (200 → 158 entries)

### Fixed
- Stage 3 level estimation accuracy: resolved ~32% overestimation in JA caused by katakana loanword contamination, low `RARE_RANK_LO`, and uncapped Stage 3 override

## [0.1.5] - 2026-05-02

### Added
- `/voca setup` command: first-run onboarding wizard (language selection, primary language, scan model, level test)
- Prerequisites guard: all `/voca` commands are blocked until setup is complete
- 4 new i18n UI string keys: `setup.required`, `setup.already_done`, `setup.scan_model_question`, `setup.complete`
- Quick Start section in all 3 READMEs (en/ko/ja)

### Changed
- First-run wizard moved from `/voca level` to `/voca setup`
- `/voca level` now only handles profile display and re-testing
- plugin.json name reverted from `vocatrack` to `voca` (CLI prefix stays `/voca:`)

## [0.1.4] - 2026-05-02

### Added
- `/voca scan` command: standalone trigger for full-transcript vocabulary extraction
- `/voca scan --status`: check extractor state and queue size
- 5 new i18n UI string keys: `scan.spawned`, `scan.already_running`, `scan.status_running`, `scan.status_idle`, `scan.status_queue`
- Project logo (`assets/vocatrack-logo.png`)

## [0.1.3] - 2026-05-02

### Changed
- **Service rebrand**: repo renamed from `voca-plugin` to `vocatrack`
- plugin.json name changed from `voca` to `vocatrack`
- All README and CHANGELOG URLs updated to `github.com/flame91/vocatrack`

## [0.1.2] - 2026-05-02

### Added
- Full i18n support: `lib-i18n.sh` with `t()`/`ti()` helpers, message files for ko/en/ja
- 4 new message keys: `level.test.header`, `level.test.question`, `level.show.stale_hint`, `queue.select_all_known`
- Japanese README (`README.ja.md`)
- `CLAUDE.md` developer guide for contributors
- `AGENTS.md` with i18n-audit, new-command, and release-check agent definitions
- `VOCA_CONFIG_PATH` environment variable override for config file location
- SKILL.md: Path Variables section (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`)
- SKILL.md: UI Strings table (~45 keys, ko/en/ja columns)
- Branch protection ruleset on master (PR + review required, admin bypass)

### Changed
- **Brand rename**: `vocab` → `voca` across all files (scripts, hooks, data references, skill directory)
- SKILL.md: all workflow sections now use `[key]` references instead of hardcoded Korean
- SKILL.md: hardcoded `~/.claude/` paths replaced with path variables (~57 occurrences)
- SKILL.md: column count corrected from 14 to 16
- README.md / README.ko.md restructured with real GitHub URL and feature table
- `lib-profile.sh`: English band/percentile functions now output English text (were Korean)
- `lib-profile.sh`: Japanese percentile function now outputs pure Japanese (was mixed Korean/Japanese)
- `level-options.sh`: header and question template now use i18n keys
- `level-options-verify.sh`: sentinel option filter now uses i18n key
- `level-show.sh`: stale hint now uses i18n key

### Fixed
- Removed duplicate `CONFIG_PATH` definition in `lib-config.sh` (already defined in `lib.sh`)
- Removed duplicate `PROFILE_PATH` definition in `lib-profile.sh` (already defined in `lib.sh`)
- Removed legacy `VOCAB_CONFIG` variable reference in `import-from-notion.sh`
- Command .md files: simplified verbose path resolution patterns

## [0.1.1] - 2026-04-30

### Changed
- Version bump from 0.1.0

### Fixed
- Drop redundant skills/commands/hooks fields from plugin.json
- Wrap Stop hook under top-level "hooks" key in hooks.json
- Author field corrected to object format per Claude Code plugin schema

## [0.1.0] - 2026-04-30

### Added
- Initial plugin skeleton
- TSV-backed vocabulary tracker with 16-column schema (`voca.tsv`)
- 15 slash commands: add, list, search, stats, review, rate, archive, master, restore, level, queue, config, domain, source, reclassify
- 3-stage adaptive vocabulary size estimation for en/ja/ko (modeled on testyourvocab.com)
- Stop hook auto-extraction via Haiku (background candidate detection)
- Frequency-ranked probe wordlists from FrequencyWords + Wikipedia + BCCWJ
- Queue picker UI with AskUserQuestion (multiSelect, hybrid main/subagent architecture)
- Interactive config UI (list columns, list options, picker/scan, primary language, optimize)
- Domain and source tag registries with color support
- CC BY-SA 4.0 license

[0.1.5]: https://github.com/flame91/vocatrack/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/flame91/vocatrack/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/flame91/vocatrack/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/flame91/vocatrack/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/flame91/vocatrack/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/flame91/vocatrack/releases/tag/v0.1.0
