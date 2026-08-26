#!/bin/bash
# UserPromptSubmit hook for drive mode.
# When the flag file exists (toggled by /drive-on and /drive-off), inject the
# drive contract into every prompt. Single source of truth is the skill body:
# ~/.claude/skills/drive/SKILL.md — edit the contract there, never here.
#
# The contract goes out on plain stdout, which UserPromptSubmit adds to the
# turn's context. That replaced a jq-built additionalContext envelope: jq is
# absent on plenty of machines, and because the failed pipeline still let this
# script exit 0, drive mode simply never engaged and said nothing about why.
#
# Nothing here runs a subprocess. The frontmatter strip is a copy of
# strip_frontmatter in lib.sh — this file is installed standalone and cannot
# source it — and tests/run-tests.sh asserts the two stay byte-identical, since
# a drift between them would give /drive and the standing mode two different
# contracts.

FLAG="$HOME/.claude/drive-mode"
SKILL="$HOME/.claude/skills/drive/SKILL.md"

if [ -f "$FLAG" ] && [ -f "$SKILL" ]; then
  echo "DRIVE MODE IS ON (turn off with /drive-off). Apply this operating contract to this entire turn:"
  delims=0
  re='^---[[:space:]]*$'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$delims" -ge 2 ]; then
      printf '%s\n' "$line"
    elif [[ $line =~ $re ]]; then
      delims=$((delims + 1))
    fi
  done < "$SKILL"
fi

exit 0
