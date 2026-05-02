---
description: Inspect or edit voca subsystem configuration (list columns, picker page size, scan model, …).
argument-hint: "[show|get <key>|set <key> <value>|reset]"
---

User input: `$ARGUMENTS`

Branch on `$ARGUMENTS`:

**1. Empty** (`/voca:config`) — interactive AskUserQuestion menu.
- Read `${CLAUDE_PLUGIN_ROOT}/skills/voca/SKILL.md` and execute the **Config UI** section (Stage 1 picker → Stage 2 a/b/c/d branch).

**2. With args** (`show` / `get <key>` / `set <key> <value>` / `reset`):
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/config.sh $ARGUMENTS` and paste stdout. TABLE → fenced code block; 1-line → plain.

> ⚠ Paste Bash stdout into your reply.
