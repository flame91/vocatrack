#!/usr/bin/env bash
# /voca help — print grouped command reference.
set -uo pipefail

cat <<'HELP'
━━━ Vocabulary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  add <word>          Record a new word (auto-infers meaning/tags)
  list [N] [--status] [--lang]
                      List entries (table view)
  search <query>      Case-insensitive search across word/meaning/example
  rate <word> <rating> [note]
                      Rate: memorized | learning | unsure
  review              Interactive rating session
  master <word>       Promote to mastered
  archive <word>      Archive a word
  restore <word>      Restore to active

━━━ Tags ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  domain list|add|remove
                      Manage domain tag registry
  source list|add|remove
                      Manage source tag registry
  reclassify [--all|--pending|<word>]
                      Re-infer domain tags

━━━ Queue & Scan ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  queue [--flush]     Candidate picker (from Stop hook)
  scan [--status]     Extract candidates from session

━━━ Measure & Export ━━━━━━━━━━━━━━━━━━━━━━━━━━━
  level [test|reset]  Vocabulary size estimation (CEFR)
  stats               Dashboard (lifecycle, activity, hook precision)
  export [--format] [--status] [--lang]
                      Export words (csv, anki, json, md)

━━━ Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  setup               First-run wizard
  config [show|get|set|reset]
                      Inspect or edit settings
  help                This reference
HELP
