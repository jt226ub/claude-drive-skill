#!/bin/bash
# UserPromptSubmit hook for drive mode.
# When the flag file exists (toggled by /drive-on and /drive-off), inject the
# drive contract into every prompt. Single source of truth is the skill body:
# ~/.claude/skills/drive/SKILL.md — edit the contract there, never here.
#
# The contract goes out on plain stdout, which UserPromptSubmit adds to the
# turn's context. This replaced a jq-built additionalContext envelope: jq is
# absent on plenty of machines (Windows in particular), and because the failed
# pipeline still let the script exit 0, drive mode simply never engaged and
# said nothing about why. Plain stdout has no dependency beyond awk.

FLAG="$HOME/.claude/drive-mode"
SKILL="$HOME/.claude/skills/drive/SKILL.md"

if [ -f "$FLAG" ] && [ -f "$SKILL" ]; then
  echo "DRIVE MODE IS ON (turn off with /drive-off). Apply this operating contract to this entire turn:"
  # Print everything after the closing frontmatter delimiter.
  awk 'f >= 2 { print } /^---[[:space:]]*$/ { f++ }' "$SKILL"
fi

exit 0
