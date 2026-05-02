# AGENTS.md

Specialized agents for the voca plugin repository.

---

## i18n-audit

**Description:** Verify i18n completeness -- message key sync across ko/en/ja TSV files + detect hardcoded Korean/Japanese in scripts.

**Steps:**

1. Compare keys across `messages/{ko,en,ja}.tsv` -- flag any missing or extra keys per locale
   ```bash
   # Extract key columns and diff
   cut -f1 plugins/voca/messages/ko.tsv | sort > /tmp/ko-keys
   cut -f1 plugins/voca/messages/en.tsv | sort > /tmp/en-keys
   cut -f1 plugins/voca/messages/ja.tsv | sort > /tmp/ja-keys
   diff /tmp/ko-keys /tmp/en-keys
   diff /tmp/ko-keys /tmp/ja-keys
   ```
2. Grep for Korean Unicode ranges (U+AC00-U+D7A3) in `scripts/*.sh` (excluding comments and message files) -- flag any hardcoded Korean
   ```bash
   grep -rn '[가-힣]' plugins/voca/scripts/*.sh | grep -v '^\s*#'
   ```
3. Grep for Japanese kana/kanji (U+3040-U+309F, U+30A0-U+30FF, U+4E00-U+9FFF) in `scripts/*.sh` (excluding comments) -- flag hardcoded Japanese
4. Check `skills/voca/SKILL.md` UI Strings table has entries for all `AskUserQuestion` blocks -- each block should reference a UI string key with ko/en/ja columns
5. Report findings: list all mismatches, hardcoded strings with file:line, and missing UI string entries

---

## new-command

**Description:** Checklist for adding a new `/voca` subcommand.

**Steps:**

1. Create `commands/<name>.md` with frontmatter:
   ```yaml
   ---
   description: Short description of the subcommand
   argument-hint: "<arg>" # optional
   ---
   ```
   Body should invoke the skill or script using `${CLAUDE_PLUGIN_ROOT}` paths.

2. If logic is needed: create `scripts/<name>.sh`
   - MUST source `lib.sh` as the first action
   - Use `lib-i18n.sh` for any user-facing output
   - Follow kebab-case naming

3. Add a workflow section to `skills/voca/SKILL.md`
   - Document the trigger phrases and behavior
   - Use `${CLAUDE_PLUGIN_ROOT}/scripts/` for script paths
   - Use `${CLAUDE_PLUGIN_DATA}/` for data file paths

4. If new user-facing strings in bash scripts: add keys to all 3 `messages/*.tsv` files (ko, en, ja) simultaneously

5. If new UI strings in SKILL.md `AskUserQuestion` blocks: add rows to the UI Strings table with ko/en/ja columns

6. Update README feature list in all 3 languages (README.md, README.ko.md, README.ja.md)

---

## release-check

**Description:** Pre-release verification checklist.

**Steps:**

1. **Version match**: verify `plugin.json` version matches README version mentions
   ```bash
   grep '"version"' plugins/voca/.claude-plugin/plugin.json
   grep -n 'version\|v0\.' README.md README.ko.md
   ```

2. **i18n key sync**: all `messages/*.tsv` files must have identical key sets
   ```bash
   diff <(cut -f1 plugins/voca/messages/ko.tsv | sort) <(cut -f1 plugins/voca/messages/en.tsv | sort)
   diff <(cut -f1 plugins/voca/messages/ko.tsv | sort) <(cut -f1 plugins/voca/messages/ja.tsv | sort)
   ```

3. **No hardcoded `~/.claude/` paths in SKILL.md** (except `~/.claude/projects/` which is a standard Claude Code path)
   ```bash
   grep -n '~/\.claude/' plugins/voca/skills/voca/SKILL.md | grep -v 'projects/'
   ```

4. **No hardcoded Korean in scripts**: grep for U+AC00-U+D7A3 outside comments and message files
   ```bash
   grep -rn '[가-힣]' plugins/voca/scripts/*.sh | grep -v '^\s*#'
   ```

5. **Command .md files use variable paths**: all command files should reference `${CLAUDE_PLUGIN_ROOT}` (not hardcoded absolute paths)
   ```bash
   grep -rn '/home\|/Users\|~/\.claude' plugins/voca/commands/*.md
   ```

6. **CHANGELOG.md**: verify the new version has an entry in CHANGELOG.md
   ```bash
   VERSION=$(jq -r .version plugins/voca/.claude-plugin/plugin.json)
   grep -q "\[$VERSION\]" CHANGELOG.md && echo "OK: CHANGELOG has $VERSION" || echo "MISSING: CHANGELOG entry for $VERSION"
   ```

7. **git status clean**: no uncommitted changes
   ```bash
   git status --porcelain
   ```
