#!/bin/bash
# Remove the drive skill from a Claude Code config directory.
# Leaves settings.json backups in place.
#
# Deregistration needs node or perl. When neither runs, the files still go and
# settings.json is left untouched with a note — an orphaned hook entry is
# harmless (the script it points at is gone, and a missing hook command is a
# no-op), so there is nothing worth risking a sed-edit of JSON for.

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

if [ -f "$SETTINGS" ] && grep -q 'drive-mode\.sh' "$SETTINGS"; then
  RUNTIME="$(json_runtime || true)"
  if [ -n "$RUNTIME" ]; then
    cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    tmp="$(mktemp)"
    # Drop any hook entry pointing at drive-mode.sh, then drop the
    # UserPromptSubmit key entirely if that emptied it, and the hooks key after
    # that. Entries carrying no command must be tolerated, not tripped over.
    if [ "$RUNTIME" = node ]; then
      node -e '
        const fs = require("fs");
        const [i, o] = process.argv.slice(1);
        const s = JSON.parse(fs.readFileSync(i, "utf8"));
        const h = s.hooks || {};
        const kept = (h.UserPromptSubmit || [])
          .map(g => Object.assign({}, g, {
            hooks: (g.hooks || []).filter(
              e => !String(e.command || "").includes("drive-mode.sh")),
          }))
          .filter(g => g.hooks.length > 0);
        if (kept.length) h.UserPromptSubmit = kept; else delete h.UserPromptSubmit;
        if (Object.keys(h).length) s.hooks = h; else delete s.hooks;
        fs.writeFileSync(o, JSON.stringify(s, null, 2) + "\n");
      ' "$SETTINGS" "$tmp"
    else
      perl -MJSON::PP -e '
        my ($i, $o) = @ARGV;
        open my $in, "<", $i or die "$i: $!";
        my $raw = do { local $/; <$in> };
        close $in;
        my $s = JSON::PP->new->decode($raw);
        my $h = $s->{hooks} || {};
        my @kept;
        for my $group (@{ $h->{UserPromptSubmit} || [] }) {
          my @entries = grep { ($_->{command} // "") !~ /drive-mode\.sh/ }
                             @{ $group->{hooks} || [] };
          next unless @entries;
          push @kept, { %$group, hooks => \@entries };
        }
        if (@kept) { $h->{UserPromptSubmit} = \@kept }
        else       { delete $h->{UserPromptSubmit} }
        if (%$h) { $s->{hooks} = $h } else { delete $s->{hooks} }
        open my $out, ">", $o or die "$o: $!";
        print $out JSON::PP->new->canonical->indent->space_after
          ->indent_length(2)->encode($s);
        close $out;
      ' "$SETTINGS" "$tmp"
    fi
    mv "$tmp" "$SETTINGS"
    echo "Deregistered hook from settings.json via $RUNTIME (backup written)."
  else
    cat >&2 <<EOF

NOTE: no working JSON runtime (node or perl) was found, so the hook entry is
      still in $SETTINGS. It is inert now that the script is
      deleted; remove the UserPromptSubmit entry naming drive-mode.sh by hand
      to tidy up.
EOF
  fi
fi
