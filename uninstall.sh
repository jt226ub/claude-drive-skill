#!/bin/bash
# Remove the drive skill from a Claude Code config directory.
# Leaves settings.json backups in place.

set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

rm -f "$CLAUDE_DIR/drive-mode"                 # the standing-mode flag
rm -f "$CLAUDE_DIR/skills/drive/SKILL.md"
rmdir "$CLAUDE_DIR/skills/drive" 2>/dev/null || true
rm -f "$CLAUDE_DIR/commands/drive-on.md" "$CLAUDE_DIR/commands/drive-off.md"
rm -f "$CLAUDE_DIR/hooks/drive-mode.sh"
echo "Removed drive files from $CLAUDE_DIR"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  # Drop any hook entry pointing at drive-mode.sh, then drop the UserPromptSubmit
  # key entirely if that emptied it.
  # The // [] guards matter: settings.json may have no hooks key at all, and an
  # entry may carry no command — jq would abort on null rather than no-op.
  jq '.hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
        | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("drive-mode.sh") | not))))
        | map(select((.hooks | length) > 0)))
      | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
      | if ((.hooks // {}) | length) == 0 then del(.hooks) else . end' \
    "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "Deregistered hook from settings.json (backup written)."
fi
