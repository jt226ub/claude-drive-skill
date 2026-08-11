#!/bin/bash
# UserPromptSubmit hook for drive mode.
# When the flag file exists (toggled by /drive-on and /drive-off), inject the
# drive contract into every prompt. Single source of truth is the skill body:
# ~/.claude/skills/drive/SKILL.md — edit the contract there, never here.
# Keep the skill body under ~9,000 chars: additionalContext is capped at 10,000.

FLAG="$HOME/.claude/drive-mode"
SKILL="$HOME/.claude/skills/drive/SKILL.md"

if [ -f "$FLAG" ] && [ -f "$SKILL" ]; then
  # Print everything after the closing frontmatter delimiter, then wrap it in
  # the hook's additionalContext JSON envelope.
  awk 'f >= 2 { print } /^---[[:space:]]*$/ { f++ }' "$SKILL" \
    | jq -Rs '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: ("DRIVE MODE IS ON (turn off with /drive-off). Apply this operating contract to this entire turn:\n" + .)}}'
fi

exit 0
