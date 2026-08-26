#!/bin/bash
# Remove the drive skill from a Claude Code config directory.
# Leaves settings.json backups in place, deliberately.
#
# Needs bash and nothing else — see lib.sh.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

# shellcheck source=lib.sh
. "$SRC/lib.sh"

rm -f "$CLAUDE_DIR/drive-mode"                 # the standing-mode flag
rm -f "$CLAUDE_DIR/skills/drive/SKILL.md"
rmdir "$CLAUDE_DIR/skills/drive" 2>/dev/null || true
rm -f "$CLAUDE_DIR/commands/drive-on.md" "$CLAUDE_DIR/commands/drive-off.md"
rm -f "$CLAUDE_DIR/hooks/drive-mode.sh"
echo "Removed drive files from $CLAUDE_DIR"

if [ -s "$SETTINGS" ]; then
  # Named, not globbed: the only backup this run may remove is the one this run
  # wrote. Every earlier backup stays, on purpose.
  BAK="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$BAK"
  set +e
  settings_deregister_hook "$SETTINGS" drive-mode.sh
  rc=$?
  set -e
  case $rc in
    0) echo "Deregistered hook from settings.json (backup written)." ;;
    2) echo "No drive hook in settings.json — left unchanged."
       rm -f "$BAK" ;;
    *) cat >&2 <<'SNIP'

NOTE: settings.json could not be edited safely, so it was left alone. The hook
      entry is inert now that the script it names is deleted; remove the
      UserPromptSubmit entry naming drive-mode.sh by hand to tidy up.
SNIP
       ;;
  esac
fi
