---
description: Picker UI for auto-extracted candidate vocabulary words (Stop hook queue).
---

If arguments contain `--flush`: run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/queue-clear.sh` and pass through its output. Stop.

Otherwise: read `${CLAUDE_PLUGIN_ROOT}/skills/voca/SKILL.md` and execute the **Queue** section (hybrid: main runs picker, subagent processes).
