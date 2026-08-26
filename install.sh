#!/bin/bash
# Install the drive skill into a Claude Code config directory.
#
#   ./install.sh                 # install into ~/.claude
#   CLAUDE_DIR=/path ./install.sh
#
# Idempotent: re-running overwrites the four drive files and leaves the
# settings.json hook registration alone if it is already there. The standing
# mode is NOT switched on by install — run /drive-on in Claude Code for that.
#
# Needs bash and nothing else. There is no jq, node, perl, python or awk in
# this project; lib.sh explains why at length, but the short version is that a
# missing tool is the most common way an install fails, and jq's absence used
# to fail silently.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

# shellcheck source=lib.sh
. "$SRC/lib.sh"

# In standing mode the contract rides on every prompt, so its length is a
# context cost paid per turn. This is a self-imposed budget, not a harness cap:
# the old 10,000-character additionalContext ceiling no longer applies now that
# the hook writes to stdout, but the per-turn cost was always the better reason
# to keep the contract tight. OmniRoute's own ceiling is 50,000 — one SKILL.md
# has to fit both targets, so the tighter number wins.
BODY="$(strip_frontmatter "$SRC/skills/drive/SKILL.md")"
if [ "${#BODY}" -gt 9000 ]; then
  echo "ERROR: contract body is ${#BODY} chars, over the 9,000 budget." >&2
  echo "       Trim SKILL.md — it is injected into every prompt." >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR/skills/drive" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/hooks"
cp "$SRC/skills/drive/SKILL.md"  "$CLAUDE_DIR/skills/drive/SKILL.md"
cp "$SRC/commands/drive-on.md"   "$CLAUDE_DIR/commands/drive-on.md"
cp "$SRC/commands/drive-off.md"  "$CLAUDE_DIR/commands/drive-off.md"
cp "$SRC/hooks/drive-mode.sh"    "$CLAUDE_DIR/hooks/drive-mode.sh"
chmod +x "$CLAUDE_DIR/hooks/drive-mode.sh"
echo "Installed skill, commands and hook into $CLAUDE_DIR"

# The hook script and the two slash commands resolve their paths from $HOME, so
# the portable command string only works for the default location; anywhere
# else needs the literal path.
if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then
  HOOK_CMD='"$HOME/.claude/hooks/drive-mode.sh"'
else
  HOOK_CMD="\"$CLAUDE_DIR/hooks/drive-mode.sh\""
  echo "NOTE: non-default CLAUDE_DIR — the hook and the /drive-on and"
  echo "      /drive-off commands still read the flag and the skill from"
  echo "      \$HOME/.claude. Edit those three files if that is wrong."
fi

# A missing or empty settings.json becomes an empty object first, so there is
# one registration path rather than a special case for the clean-machine
# install and another for everyone else.
EXISTED=1
if [ ! -s "$SETTINGS" ]; then
  EXISTED=0
  printf '{}\n' > "$SETTINGS"
fi

if settings_hook_registered "$SETTINGS" drive-mode.sh; then
  echo "Hook already registered in settings.json — left unchanged."
else
  if [ "$EXISTED" = 1 ]; then
    cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  fi
  if settings_register_hook "$SETTINGS" "$HOOK_CMD"; then
    if [ "$EXISTED" = 1 ]; then
      echo "Registered UserPromptSubmit hook in settings.json (backup written)."
    else
      echo "Wrote $SETTINGS with the UserPromptSubmit hook registered."
    fi
  else
    # settings_register_hook refuses rather than guesses when the file is not
    # JSON, or when "hooks" holds something other than an object. It has
    # already said which; all that is left is to show what to paste.
    json_escape HOOK_CMD_JSON "$HOOK_CMD"
    cat >&2 <<SNIP

      settings.json was left untouched. Add this yourself, merging into an
      existing "hooks" key rather than replacing it:

  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "$HOOK_CMD_JSON" } ] }
    ]
  }

      Files are in place; that edit is all that is missing.
SNIP
    exit 1
  fi
fi

echo
echo "Done. Restart Claude Code, then:"
echo "  /drive       run one task under the contract"
echo "  /drive-on    standing mode until /drive-off"
