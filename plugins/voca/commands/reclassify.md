---
description: Re-tag previously added words (domain/source) using current conventions and registry.
argument-hint: "[--word=...] [--lang=...] [--limit=N]"
---

User input: `$ARGUMENTS`

Read `${CLAUDE_PLUGIN_ROOT}/skills/vocab/SKILL.md` and execute the **Reclassify** section.

Iterate over matching rows in `vocab.tsv`, propose new tags inferred from `meaning`/`example`/`context`, and confirm with the user before writing back.
