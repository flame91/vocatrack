---
description: Picker UI for auto-extracted candidate vocabulary words (Stop hook queue).
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/voca/SKILL.md` and execute the **Queue** section (hybrid: main runs picker, subagent processes).

If the queue is empty, spawn the async extractor on the latest transcript and reply that the user can re-run `/voca:queue` in 30–60s.

Otherwise, surface up to 15 unshown candidates via AskUserQuestion (multiSelect) with a final `[queue.select_all_known]` option (see SKILL.md UI Strings table), then hand off accepted/rejected lists to a `general-purpose` subagent for per-word inference + log writes + queue cleanup.
