---
description: Manage domain tag registry (list / add / remove).
argument-hint: "list | add <name> [color] | remove <name>"
---

User input: `$ARGUMENTS`

Branch on first token of `$ARGUMENTS`:

| sub | script | output |
|---|---|---|
| `list` | `domain-list.sh` | TABLE → fenced code block |
| `add <name> [color]` | `domain-add.sh` | 1-line → plain |
| `remove <name>` | `domain-remove.sh` | 1-line → plain (also strips tag from any matching voca.tsv row) |

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/domain-<sub>.sh <args>
```

Allowed colors: gray, brown, orange, yellow, green, blue, purple, pink, red, default.

> ⚠ Paste Bash stdout into your reply.
