#!/usr/bin/env bash
# Setup completion guard. Used as a one-shot prelude by /voca:* commands so the
# model can pass output through verbatim instead of resolving message keys itself.
#
# Usage:
#   setup-guard.sh require   — fail if setup NOT done       (used by every command except /voca setup)
#   setup-guard.sh forbid    — fail if setup IS already done (used by /voca setup itself)
#
# Output convention:
#   - Silent stdout + exit 0  → guard passed; caller continues.
#   - Non-empty stdout        → guard tripped; caller prints it verbatim and stops.
#                                (exit code is also 0 to keep consumers simple.)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
. "$SCRIPT_DIR/lib-i18n.sh"
. "$SCRIPT_DIR/lib-profile.sh"

mode="${1:-require}"
state=$(profile_first_run_state)

case "$mode" in
  require)
    [[ "$state" == "completed" ]] || t setup.required
    ;;
  forbid)
    [[ "$state" == "completed" ]] && t setup.already_done
    ;;
  *)
    echo "usage: setup-guard.sh [require|forbid]" >&2
    exit 2
    ;;
esac
