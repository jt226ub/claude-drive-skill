#!/bin/bash
# Push the drive contract into OmniRoute's Global System Prompt.
#
#   ./omniroute/install-omniroute.sh                    # local gateway on :20128
#   OMNIROUTE_BASE_URL=http://host:20128 ./omniroute/install-omniroute.sh
#   OMNIROUTE_CLI=/path/to/OmniRoute/bin/omniroute.mjs ./omniroute/install-omniroute.sh
#
# Unlike install.sh (which targets a Claude Code hook), this applies the contract
# server-side, so EVERY client and model routed through the gateway receives it and
# no client can opt out. skills/drive/SKILL.md stays the single source of truth —
# this script never edits the contract, it only ships it.
#
# Idempotent: re-running overwrites the stored prompt with the current SKILL.md.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$SRC/skills/drive/SKILL.md"
BASE="${OMNIROUTE_BASE_URL:-http://127.0.0.1:20128}"

[ -f "$SKILL" ] || { echo "ERROR: missing $SKILL" >&2; exit 1; }

# Resolve the OmniRoute CLI: explicit override, then PATH, then a sibling checkout.
if [ -n "${OMNIROUTE_CLI:-}" ]; then
  CLI=(node "$OMNIROUTE_CLI")
elif command -v omniroute >/dev/null 2>&1; then
  CLI=(omniroute)
else
  echo "ERROR: cannot find the omniroute CLI." >&2
  echo "       Put it on PATH, or set OMNIROUTE_CLI=/path/to/bin/omniroute.mjs" >&2
  exit 1
fi

command -v python3 >/dev/null || { echo "ERROR: python3 is required." >&2; exit 1; }

# Strip YAML frontmatter with the same rule the Claude Code hook uses, so both
# deployment paths inject byte-identical text.
BODY="$(awk 'f >= 2 { print } /^---[[:space:]]*$/ { f++ }' "$SKILL")"
CHARS=${#BODY}
# OmniRoute caps prefixPrompt at 50,000; the 9,000 guard from install.sh is kept so
# one SKILL.md stays deployable to BOTH targets without divergence.
if [ "$CHARS" -gt 9000 ]; then
  echo "ERROR: contract body is $CHARS chars (>9000)." >&2
  echo "       It would still fit OmniRoute, but would break the Claude Code hook." >&2
  echo "       Keep one contract that fits both — trim SKILL.md." >&2
  exit 1
fi

PAYLOAD="$(mktemp)"
trap 'rm -f "$PAYLOAD"' EXIT
BODY="$BODY" python3 -c '
import json, os, sys
header = ("DRIVE MODE IS ALWAYS ON. It is a binding operating contract for this and every "
          "response. Apply it in full:\n\n")
body = os.environ["BODY"].strip()
json.dump({"enabled": True, "prefixPrompt": header + body, "suffixPrompt": ""},
          open(sys.argv[1], "w"))
' "$PAYLOAD"

echo "Contract: $CHARS chars  ->  $BASE"
OMNIROUTE_BASE_URL="$BASE" "${CLI[@]}" api settings put-api-settings-system-prompt \
  --body "@$PAYLOAD" >/dev/null

# Read it back — never report success on an unverified write.
OMNIROUTE_BASE_URL="$BASE" "${CLI[@]}" api settings get-api-settings-system-prompt \
  --output json 2>/dev/null \
  | python3 -c '
import sys, json
raw = sys.stdin.read()
# The CLI prefixes human-readable env notices; the payload starts at the first brace.
i = raw.find("{")
if i < 0:
    print("WARNING: no JSON in read-back; verify in the dashboard.")
    sys.exit(0)
try:
    d = json.loads(raw[i:])
except Exception as e:
    print("WARNING: unparsable read-back (%s); verify in the dashboard." % e)
    sys.exit(0)
n = len(d.get("prefixPrompt") or "")
ok = bool(d.get("enabled")) and n > 0
print("Verified: enabled=%s  stored=%s chars" % (d.get("enabled"), n))
sys.exit(0 if ok else 1)
'
echo "Done. Every client through this gateway now receives the contract."
