---
description: Show / measure / reset vocabulary size estimate (en, ja, ko). 3-stage adaptive test.
argument-hint: "[test [en|ja|ko]] | [reset [en|ja|ko|all]]"
---

User input: `$ARGUMENTS`

Branch on `$ARGUMENTS`:

**1. Empty** (`/voca:level`) — show current profile.
- If `${VOCA_STATE_DIR:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/state}}/vocab-profile.json` is missing OR every language has `spoken: false` → run **Setup Wizard** from `${CLAUDE_PLUGIN_ROOT}/skills/vocab/SKILL.md`.
- Otherwise → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/level-show.sh` and paste stdout verbatim as a fenced code block.

**2. `test [lang]`** (`/voca:level test ko`) — adaptive measurement.
- Read `${CLAUDE_PLUGIN_ROOT}/skills/vocab/SKILL.md` and execute the **Test Flow** section for the chosen language.
- If `lang` omitted, ask once via AskUserQuestion (`en` / `ja` / `ko`).

**3. `reset [lang|all]`** (`/voca:level reset ko`) — wipe stored measurement.
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/level-reset.sh --lang <arg>` and paste the 1-line confirmation.

> ⚠ Paste every Bash stdout in your reply. Multi-line → fenced code block; 1-line → plain text.
