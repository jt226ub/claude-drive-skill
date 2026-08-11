#!/bin/bash
# Install the drive skill into a Claude Code config directory.
#
#   ./install.sh                 # install into ~/.claude
#   CLAUDE_DIR=/path ./install.sh
#
# Idempotent: re-running overwrites the four drive files and leaves the
# settings.json hook registration alone if it is already there. The standing
# mode is NOT switched on by install — run /drive-on in Claude Code for that.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

# additionalContext is capped at 10,000 chars by the harness; the hook injects
# the whole contract body, so a bloated SKILL.md would be silently truncated.
BODY_CHARS=$(awk 'f >= 2 { print } /^---[[:space:]]*$/ { f++ }' \
  "$SRC/skills/drive/SKILL.md" | wc -c | tr -d ' ')
if [ "$BODY_CHARS" -gt 9000 ]; then
  echo "ERROR: contract body is $BODY_CHARS chars; the 10,000-char" >&2
  echo "       additionalContext cap would truncate it. Trim SKILL.md." >&2
  exit 1
fi

command -v jq >/dev/null || { echo "ERROR: jq is required (brew install jq)." >&2; exit 1; }

mkdir -p "$CLAUDE_DIR/skills/drive" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/hooks"
cp "$SRC/skills/drive/SKILL.md"  "$CLAUDE_DIR/skills/drive/SKILL.md"
cp "$SRC/commands/drive-on.md"   "$CLAUDE_DIR/commands/drive-on.md"
cp "$SRC/commands/drive-off.md"  "$CLAUDE_DIR/commands/drive-off.md"
cp "$SRC/hooks/drive-mode.sh"    "$CLAUDE_DIR/hooks/drive-mode.sh"
chmod +x "$CLAUDE_DIR/hooks/drive-mode.sh"
echo "Installed skill, commands and hook into $CLAUDE_DIR"

# The hook script resolves its own paths from $HOME, so the portable command
# string only works for the default location; anywhere else needs the literal.
if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then
  HOOK_CMD='"$HOME/.claude/hooks/drive-mode.sh"'
else
  HOOK_CMD="\"$CLAUDE_DIR/hooks/drive-mode.sh\""
  echo "NOTE: non-default CLAUDE_DIR — the hook still reads the flag and skill"
  echo "      from \$HOME/.claude; edit hooks/drive-mode.sh if that is wrong."
fi

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || { echo "ERROR: $SETTINGS is not valid JSON." >&2; exit 1; }

if jq -e --arg cmd "$HOOK_CMD" \
     '[.hooks.UserPromptSubmit[]?.hooks[]?.command] | index($cmd)' \
     "$SETTINGS" >/dev/null; then
  echo "Hook already registered in settings.json — left unchanged."
else
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"
  jq --arg cmd "$HOOK_CMD" \
    '.hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) +
       [{hooks: [{type: "command", command: $cmd}]}])' \
    "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "Registered UserPromptSubmit hook in settings.json (backup written)."
fi

echo
echo "Done. Restart Claude Code, then:"
echo "  /drive       run one task under the contract"
echo "  /drive-on    standing mode until /drive-off"
