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
# Nothing here requires jq, or any JSON runtime at all on a clean machine: a
# missing or empty settings.json is written whole, and only merging into an
# existing one needs node or perl. When neither runs, the file is left
# untouched and the snippet is printed to paste by hand. See README "No jq".

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

# shellcheck source=lib.sh
. "$SRC/lib.sh"

# In standing mode the contract rides on every prompt, so its size is a running
# context cost paid per turn. This is a self-imposed budget, not a harness cap.
BODY_CHARS=$(awk 'f >= 2 { print } /^---[[:space:]]*$/ { f++ }' \
  "$SRC/skills/drive/SKILL.md" | wc -c | tr -d ' ')
if [ "$BODY_CHARS" -gt 9000 ]; then
  echo "ERROR: contract body is $BODY_CHARS chars, over the 9,000 budget." >&2
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

# The hook script resolves its own paths from $HOME, so the portable command
# string only works for the default location; anywhere else needs the literal.
if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then
  HOOK_CMD='"$HOME/.claude/hooks/drive-mode.sh"'
else
  HOOK_CMD="\"$CLAUDE_DIR/hooks/drive-mode.sh\""
  echo "NOTE: non-default CLAUDE_DIR — the hook still reads the flag and skill"
  echo "      from \$HOME/.claude; edit hooks/drive-mode.sh if that is wrong."
fi
HOOK_CMD_JSON="\"$(json_escape "$HOOK_CMD")\""

MANUAL=0

if [ ! -s "$SETTINGS" ] || [ "$(tr -d '[:space:]' < "$SETTINGS")" = "{}" ]; then
  # Nothing to preserve, so the whole file can be written without parsing it.
  cat > "$SETTINGS" <<EOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": $HOOK_CMD_JSON
          }
        ]
      }
    ]
  }
}
EOF
  echo "Wrote $SETTINGS with the UserPromptSubmit hook registered."

elif grep -q 'drive-mode\.sh' "$SETTINGS"; then
  # Substring test rather than a structural one so this stays dependency-free.
  # It over-matches if drive-mode.sh is named anywhere else in the file, which
  # would skip registration — rare, and visible in the message below.
  echo "Hook already registered in settings.json — left unchanged."

else
  RUNTIME="$(json_runtime || true)"
  if [ -n "$RUNTIME" ]; then
    cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    tmp="$(mktemp)"
    # Write through a temp file: a parse failure or a crash must not be able to
    # leave settings.json truncated.
    if [ "$RUNTIME" = node ]; then
      node -e '
        const fs = require("fs");
        const [i, o, c] = process.argv.slice(1);
        const s = JSON.parse(fs.readFileSync(i, "utf8"));
        s.hooks = s.hooks || {};
        s.hooks.UserPromptSubmit = s.hooks.UserPromptSubmit || [];
        s.hooks.UserPromptSubmit.push({hooks: [{type: "command", command: c}]});
        fs.writeFileSync(o, JSON.stringify(s, null, 2) + "\n");
      ' "$SETTINGS" "$tmp" "$HOOK_CMD"
    else
      perl -MJSON::PP -e '
        my ($i, $o, $c) = @ARGV;
        open my $in, "<", $i or die "$i: $!";
        my $raw = do { local $/; <$in> };
        close $in;
        my $s = JSON::PP->new->decode($raw);
        $s->{hooks} ||= {};
        $s->{hooks}{UserPromptSubmit} ||= [];
        push @{ $s->{hooks}{UserPromptSubmit} },
          { hooks => [ { type => "command", command => $c } ] };
        open my $out, ">", $o or die "$o: $!";
        print $out JSON::PP->new->canonical->indent->space_after
          ->indent_length(2)->encode($s);
        close $out;
      ' "$SETTINGS" "$tmp" "$HOOK_CMD"
    fi
    mv "$tmp" "$SETTINGS"
    echo "Registered UserPromptSubmit hook in settings.json via $RUNTIME (backup written)."
  else
    MANUAL=1
    cat >&2 <<EOF

NOTE: settings.json already has content and no working JSON runtime (node or
      perl) was found, so it was left untouched — merging it by hand is
      safer than editing JSON with sed. Add this to $SETTINGS,
      merging into an existing "hooks" key rather than replacing it:

  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": $HOOK_CMD_JSON } ] }
    ]
  }
EOF
  fi
fi

echo
if [ "$MANUAL" = 1 ]; then
  echo "Files are in place; the settings.json edit above is still to do. Then:"
else
  echo "Done. Restart Claude Code, then:"
fi
echo "  /drive       run one task under the contract"
echo "  /drive-on    standing mode until /drive-off"
