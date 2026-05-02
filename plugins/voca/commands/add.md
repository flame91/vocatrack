---
description: Record a new word. Infers meaning/example/context/tags from conversation, dedups against voca.tsv.
argument-hint: "[word]"
---

User input: `$ARGUMENTS`

Read `${CLAUDE_PLUGIN_ROOT}/skills/voca/SKILL.md` and execute the **Add a word** section.

If `$ARGUMENTS` is empty AND the user said "그 단어" / "방금 단어" / "that word", check `${CLAUDE_PLUGIN_DATA}/voca-candidates.json` first.

Reply with the 1-line confirmation that `add.sh` printed (e.g. `Added "ephemeral" — 잠시 동안만 존재하는, 일시적인.`). Don't echo the JSON or paraphrase.
