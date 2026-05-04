---
description: List recent vocabulary entries (table view). Add --manage / -m for an interactive bulk picker (rate / master / archive).
argument-hint: "[N] [--status=active|mastered|archived|all] [--lang=en|ja|ko|mixed|other|all] [--manage|-m]"
---

> ⚠ Claude Code UI auto-collapses Bash stdout. **Paste the script output verbatim as a fenced code block** in your reply — anything left only in the tool result is invisible to the user.

**Step 1 — render the table.** `list.sh` consumes `--manage` / `-m` itself (no-op for table render):

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/list.sh $ARGUMENTS
```

Emit the stdout into your reply inside a fenced code block.

**Step 2 — Manage flow (only if `$ARGUMENTS` contains `--manage` or `-m`).** Read the **Manage** section of `${CLAUDE_PLUGIN_ROOT}/skills/voca/SKILL.md` and execute it. Briefly:

1. Strip `--manage` / `-m` from the original args → `$FILTER_ARGS`.
2. `ROWS_JSON=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/list.sh --json $FILTER_ARGS)` — same filter set as the table.
3. AskUserQuestion picker (multi-select, up to 16 words, 4 questions × 2–4 options each).
4. AskUserQuestion action question (single-select: memorized / learning / unsure / master / archive / cancel).
5. Dispatch each selected word to `rate.sh` / `master.sh` / `archive.sh` accordingly.
6. Print the one-line `[manage.done]` summary. If >16 rows, offer `[manage.continue]` for the next batch.

If `$ARGUMENTS` does **not** contain `--manage` / `-m`, stop after Step 1.
