---
description: Manage source tag registry (list / add / remove).
argument-hint: "list | add <name> [color] | remove <name>"
---

User input: `$ARGUMENTS`

Branch on first token of `$ARGUMENTS`:

| sub | script | output |
|---|---|---|
| `list` | `source-list.sh` | TABLE → fenced code block |
| `add <name> [color]` | `source-add.sh` | 1-line → plain |
| `remove <name>` | `source-remove.sh` | 1-line → plain (also strips tag from matching rows) |

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/source-<sub>.sh <args>
```

Allowed colors: gray, brown, orange, yellow, green, blue, purple, pink, red, default.

> ⚠ Paste Bash stdout into your reply.
