#!/bin/bash
# Push the drive contract into OmniRoute's Global System Prompt.
#
#   ./omniroute/install-omniroute.sh                    # local gateway on :20128
#   OMNIROUTE_BASE_URL=http://host:20128 ./omniroute/install-omniroute.sh
#   OMNIROUTE_CLI=/path/to/OmniRoute/bin/omniroute.mjs ./omniroute/install-omniroute.sh
#
# Unlike install.sh, which targets a Claude Code hook, this applies the contract
# server-side: every client and model routed through the gateway receives it and
# no client can opt out. skills/drive/SKILL.md stays the single source of truth —
# this script never edits the contract, it only ships it.
#
# Idempotent: re-running overwrites the stored prompt with the current SKILL.md.
#
# The only thing this needs beyond bash is the omniroute CLI itself. It used to
# shell out to python3 to build and read back the JSON; that is now pure bash in
# lib.sh, so nothing is required here that the gateway did not already require.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$SRC/skills/drive/SKILL.md"
BASE="${OMNIROUTE_BASE_URL:-http://127.0.0.1:20128}"

# shellcheck source=../lib.sh
. "$SRC/lib.sh"

[ -f "$SKILL" ] || { echo "ERROR: missing $SKILL" >&2; exit 1; }

# Resolve the OmniRoute CLI: explicit override, then PATH, then give up.
if [ -n "${OMNIROUTE_CLI:-}" ]; then
  CLI=(node "$OMNIROUTE_CLI")
elif command -v omniroute >/dev/null 2>&1; then
  CLI=(omniroute)
else
  echo "ERROR: cannot find the omniroute CLI." >&2
  echo "       Put it on PATH, or set OMNIROUTE_CLI=/path/to/bin/omniroute.mjs" >&2
  exit 1
fi

# Strip the frontmatter with the same rule hooks/drive-mode.sh uses, so both
# deployment paths ship byte-identical text.
BODY="$(strip_frontmatter "$SKILL")"
BODY=${BODY#"${BODY%%[![:space:]]*}"}          # drop the leading blank line

# OmniRoute caps prefixPrompt at 50,000; install.sh's 9,000 budget is kept here
# so one SKILL.md stays deployable to BOTH targets without divergence.
if [ "${#BODY}" -gt 9000 ]; then
  echo "ERROR: contract body is ${#BODY} chars (>9000)." >&2
  echo "       It would still fit OmniRoute, but it is over the budget that" >&2
  echo "       keeps one contract deployable to both targets — trim SKILL.md." >&2
  exit 1
fi

HEADER="DRIVE MODE IS ALWAYS ON. It is a binding operating contract for this and every response. Apply it in full:

"
json_escape SENT "$HEADER$BODY"

PAYLOAD="$(mktemp)"
READBACK="$(mktemp)"
trap 'rm -f "$PAYLOAD" "$READBACK"' EXIT
printf '{"enabled":true,"prefixPrompt":"%s","suffixPrompt":""}' "$SENT" > "$PAYLOAD"

echo "Contract: ${#BODY} chars  ->  $BASE"
OMNIROUTE_BASE_URL="$BASE" "${CLI[@]}" api settings put-api-settings-system-prompt \
  --body "@$PAYLOAD" >/dev/null

# Read it back — never report success on an unverified write.
OMNIROUTE_BASE_URL="$BASE" "${CLI[@]}" api settings get-api-settings-system-prompt \
  --output json > "$READBACK" 2>/dev/null || true

if ! json_field ENABLED "$READBACK" enabled; then
  echo "WARNING: no readable payload came back; verify in the dashboard." >&2
  exit 1
fi
if ! json_field STORED "$READBACK" prefixPrompt; then
  echo "WARNING: the response carried no prefixPrompt; verify in the dashboard." >&2
  exit 1
fi

# Both figures count *encoded* characters, so they are comparable without
# decoding the string back out of JSON. An equal count is the check that
# matters: a gateway that truncated the contract would come back short, which
# is the one failure this read-back exists to catch. A gateway that merely
# re-encodes it — \/ for /, — for an em dash — would also differ, hence a
# warning rather than a hard failure.
SENT_LEN=${#SENT}
STORED_LEN=$(( ${#STORED} - 2 ))               # drop the surrounding quotes

if [ "$ENABLED" != true ]; then
  echo "WARNING: stored, but enabled=$ENABLED — the gateway will not apply it." >&2
  exit 1
fi
if [ "$STORED_LEN" != "$SENT_LEN" ]; then
  echo "Verified: enabled=true, but stored $STORED_LEN encoded chars against $SENT_LEN sent."
  echo "WARNING: lengths differ — check the dashboard for a truncated contract." >&2
  exit 1
fi

echo "Verified: enabled=true, $STORED_LEN encoded chars stored, matching what was sent."
echo "Done. Every client through this gateway now receives the contract."
