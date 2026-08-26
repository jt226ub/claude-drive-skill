#!/bin/bash
# Test suite for the drive installer.
#
#   ./tests/run-tests.sh
#
# The reason this exists: install.sh edits settings.json with a JSON scanner
# written in bash rather than with jq. That trade buys a dependency-free
# install, and it is only defensible if the scanner is held to evidence. These
# tests are that evidence.
#
# Independent JSON validation uses python3 when it is present. It is a
# developer-machine convenience only — nothing in the installed product needs
# it — and when it is absent those checks report SKIP rather than passing
# quietly.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP + 1)); printf '  skip  %s\n' "$1"; }
group(){ printf '\n%s\n' "$1"; }

HAVE_PY=0
command -v python3 >/dev/null 2>&1 && python3 -c '' 2>/dev/null && HAVE_PY=1

# assert_json FILE LABEL — the file parses as JSON.
assert_json() {
  if [ "$HAVE_PY" = 0 ]; then skip "$2 (no python3 to validate with)"; return; fi
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null; then
    ok "$2"
  else
    bad "$2" "$(cat "$1")"
  fi
}

# assert_eq EXPECTED ACTUAL LABEL
assert_eq() {
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "expected [$1] got [$2]"; fi
}

# hook_commands FILE — every UserPromptSubmit command, one per line.
hook_commands() {
  [ "$HAVE_PY" = 1 ] || return 1
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for g in d.get("hooks",{}).get("UserPromptSubmit",[]):
    for e in g.get("hooks",[]):
        print(e.get("command",""))
' "$1"
}

. "$ROOT/lib.sh"
CMD='"$HOME/.claude/hooks/drive-mode.sh"'

# ---------------------------------------------------------------------------
group "Dependency floor — the whole point of the rewrite"
# ---------------------------------------------------------------------------
# Comments in these files talk about jq and node constantly; executable lines
# may not. Truncating each line at the first # is approximate — it also cuts a
# literal # inside a string — but it only ever removes text from the search, and
# these scripts have no such string.
AUDIT_TOOLS="jq perl python python3 awk sed node"
for f in install.sh uninstall.sh lib.sh hooks/drive-mode.sh omniroute/install-omniroute.sh; do
  found=""
  while IFS= read -r line; do
    line=${line%%#*}
    [ -n "$line" ] || continue
    for tool in $AUDIT_TOOLS; do
      # node is the interpreter for OmniRoute's own CLI, which that script
      # cannot work without; it is not a dependency this project introduces.
      if [ "$tool" = node ] && [ "$f" = omniroute/install-omniroute.sh ]; then continue; fi
      re="(^|[^A-Za-z0-9_./-])$tool([^A-Za-z0-9_-]|$)"
      if [[ $line =~ $re ]]; then found="$found $tool"; fi
    done
  done < "$ROOT/$f"
  if [ -z "$found" ]; then
    ok "$f invokes none of: $AUDIT_TOOLS"
  else
    bad "$f invokes$found"
  fi
done

# ---------------------------------------------------------------------------
group "Frontmatter — the hook and lib.sh must never drift"
# ---------------------------------------------------------------------------
hook_strip() {                     # exactly the loop inside hooks/drive-mode.sh
  local delims=0 line
  local re='^---[[:space:]]*$'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$delims" -ge 2 ]; then printf '%s\n' "$line"
    elif [[ $line =~ $re ]]; then delims=$((delims + 1)); fi
  done < "$1"
}
# Pull the real loop out of the hook so this compares shipped code, not a copy
# of a copy: run the hook itself against a fake HOME.
FAKEHOME="$WORK/home"; mkdir -p "$FAKEHOME/.claude/skills/drive"
run_hook() {
  cp "$1" "$FAKEHOME/.claude/skills/drive/SKILL.md"
  touch "$FAKEHOME/.claude/drive-mode"
  HOME="$FAKEHOME" bash "$ROOT/hooks/drive-mode.sh" | tail -n +2
}

printf -- '---\nname: x\n---\n\nbody line 1\n\n## head\nbody line 2\n' > "$WORK/fm-plain.md"
printf -- '---\nname: x\n---   \n\nbody\n--- \nstill body\n' > "$WORK/fm-inner-delim.md"
printf -- '---\nname: x\n---\n\nno trailing newline' > "$WORK/fm-no-nl.md"
printf -- '---\r\nname: x\r\n---\r\n\r\nbody crlf\r\n' > "$WORK/fm-crlf.md"
for f in "$WORK"/fm-*.md "$ROOT/skills/drive/SKILL.md"; do
  n="$(basename "$f")"
  a="$(strip_frontmatter "$f")"
  b="$(run_hook "$f")"
  assert_eq "$a" "$b" "lib.sh and the hook agree on $n"
done
# The blank line right after the closing --- is part of the body — the awk rule
# this replaced printed it too, and $( ) strips only trailing newlines.
assert_eq "
body line 1

## head
body line 2" "$(strip_frontmatter "$WORK/fm-plain.md")" "frontmatter body is exact"
assert_eq "
body
--- 
still body" "$(strip_frontmatter "$WORK/fm-inner-delim.md")" "a --- inside the body survives"

# ---------------------------------------------------------------------------
group "json_escape"
# ---------------------------------------------------------------------------
json_escape E 'plain/path.sh'          ; assert_eq 'plain/path.sh' "$E" "leaves a plain path alone"
json_escape E 'a"b\c'                  ; assert_eq 'a\"b\\c'       "$E" "escapes quote and backslash"
json_escape E "$(printf 'a\tb')"       ; assert_eq 'a\tb'          "$E" "escapes a tab"
json_escape E 'a
b'                                     ; assert_eq 'a\nb'          "$E" "escapes a newline"
if json_escape E "$(printf 'a\001b')" 2>/dev/null; then
  bad "rejects a raw control character" "accepted it"
else
  ok "rejects a raw control character"
fi

# ---------------------------------------------------------------------------
group "settings.json — register"
# ---------------------------------------------------------------------------
fixture() { printf '%s' "$2" > "$WORK/$1.json"; echo "$WORK/$1.json"; }

f_empty=$(fixture empty '{}')
f_none=$(fixture none '{
  "model": "opus[1m]",
  "theme": "auto"
}
')
f_hooks_only=$(fixture hooksonly '{
  "hooks": {
    "PostToolUse": [
      { "hooks": [ { "type": "command", "command": "echo hi" } ] }
    ]
  }
}
')
f_ups=$(fixture ups '{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "other.sh" } ] }
    ]
  }
}
')
f_min=$(fixture min '{"model":"opus","hooks":{"UserPromptSubmit":[]}}')
f_tabs=$(fixture tabs "$(printf '{\n\t"model": "opus",\n\t"hooks": {\n\t\t"UserPromptSubmit": []\n\t}\n}\n')")
# Modelled on a real settings.json: a long multi-line array of prose strings
# carrying quotes, backticks, parentheses and em dashes, sitting before the
# hooks key. This is the shape that first proved the scanner on real data.
f_prose=$(fixture prose '{
  "model": "opus[1m]",
  "autoMode": {
    "environment": [
      "### Org-wide",
      "**Repository visibility**: assume private unless the remote host says otherwise",
      "**Source control**: the trusted repo (this working directory) — no remotes yet",
      "**Sensitive remote targets**: any name carrying `prod` as a segment (e.g. `prod-db`, not `producer`)",
      "**Default branches**: unknown — origin/HEAD unset, and \"gh\" lookup unavailable"
    ]
  },
  "theme": "auto"
}
')
f_uni=$(fixture uni '{
  "note": "em—dash, curly “quotes”, emoji 🚀, backslash \\ and \"quoted\"",
  "model": "opus"
}
')

for pair in "empty:$f_empty" "none:$f_none" "hooksonly:$f_hooks_only" "ups:$f_ups" "min:$f_min" "tabs:$f_tabs" "uni:$f_uni" "prose:$f_prose"; do
  name=${pair%%:*}; file=${pair#*:}
  if settings_register_hook "$file" "$CMD" >/dev/null 2>&1; then
    assert_json "$file" "register into $name produces valid JSON"
    if [ "$HAVE_PY" = 1 ]; then
      if hook_commands "$file" | grep -qxF "$CMD"; then ok "register into $name lands the command"
      else bad "register into $name lands the command" "$(hook_commands "$file")"; fi
    fi
    if settings_hook_registered "$file" drive-mode.sh; then ok "register into $name is then detected"
    else bad "register into $name is then detected"; fi
  else
    bad "register into $name" "returned non-zero"
  fi
done

# The foreign entry must survive alongside ours.
if [ "$HAVE_PY" = 1 ]; then
  assert_eq "other.sh
$CMD" "$(hook_commands "$f_ups")" "an existing UserPromptSubmit entry is kept"
fi

# Unrelated settings must survive untouched.
if [ "$HAVE_PY" = 1 ]; then
  assert_eq 'em—dash, curly “quotes”, emoji 🚀, backslash \ and "quoted"' \
    "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["note"])' "$f_uni")" \
    "unicode and escapes in an unrelated key survive"
fi

# ---------------------------------------------------------------------------
group "settings.json — deregister"
# ---------------------------------------------------------------------------
for pair in "empty:$f_empty" "none:$f_none" "hooksonly:$f_hooks_only" "ups:$f_ups" "min:$f_min" "tabs:$f_tabs" "uni:$f_uni" "prose:$f_prose"; do
  name=${pair%%:*}; file=${pair#*:}
  settings_deregister_hook "$file" drive-mode.sh >/dev/null 2>&1
  rc=$?
  assert_eq 0 "$rc" "deregister from $name reports a change"
  assert_json "$file" "deregister from $name leaves valid JSON"
  if settings_hook_registered "$file" drive-mode.sh; then
    bad "deregister from $name actually removes it"
  else
    ok "deregister from $name actually removes it"
  fi
done

if [ "$HAVE_PY" = 1 ]; then
  assert_eq "other.sh" "$(hook_commands "$f_ups")" "deregister keeps the foreign entry"
  assert_eq "echo hi" "$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d["hooks"]["PostToolUse"][0]["hooks"][0]["command"])' "$f_hooks_only")" \
    "deregister leaves an unrelated hook event alone"
fi

settings_deregister_hook "$f_none" drive-mode.sh >/dev/null 2>&1
assert_eq 2 "$?" "deregister with nothing to remove reports no-change"

if [ "$HAVE_PY" = 1 ]; then
  assert_eq '**Default branches**: unknown — origin/HEAD unset, and "gh" lookup unavailable' \
    "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["autoMode"]["environment"][-1])' "$f_prose")" \
    "a long prose array survives register and deregister untouched"
fi

# ---------------------------------------------------------------------------
group "settings.json — refusals"
# ---------------------------------------------------------------------------
printf 'not json at all' > "$WORK/bad.json"
if settings_register_hook "$WORK/bad.json" "$CMD" >/dev/null 2>&1; then
  bad "refuses a non-JSON settings.json"
else
  assert_eq 'not json at all' "$(cat "$WORK/bad.json")" "refuses a non-JSON settings.json and leaves it byte-identical"
fi
printf '{"hooks": "surprise"}' > "$WORK/oddhooks.json"
if settings_register_hook "$WORK/oddhooks.json" "$CMD" >/dev/null 2>&1; then
  bad "refuses a hooks key that is not an object"
else
  assert_eq '{"hooks": "surprise"}' "$(cat "$WORK/oddhooks.json")" "refuses a hooks key that is not an object, leaving it alone"
fi

# ---------------------------------------------------------------------------
group "Invariants held by construction"
# ---------------------------------------------------------------------------
writers="$(grep -cE '^\s*JDOC=' "$ROOT/lib.sh")"
assert_eq 1 "$writers" "_j_set is the only assignment to JDOC (a stale chunk index would corrupt reads)"

# ---------------------------------------------------------------------------
group "install.sh / uninstall.sh end to end"
# ---------------------------------------------------------------------------
E2E="$WORK/claude"
mkdir -p "$E2E"
ORIGINAL='{
  "model": "opus[1m]",
  "permissions": { "allow": ["Bash(git status:*)"] }
}
'
printf '%s' "$ORIGINAL" > "$E2E/settings.json"

if CLAUDE_DIR="$E2E" bash "$ROOT/install.sh" > "$WORK/install.log" 2>&1; then
  ok "install.sh exits clean"
else
  bad "install.sh exits clean" "$(cat "$WORK/install.log")"
fi
for want in skills/drive/SKILL.md commands/drive-on.md commands/drive-off.md hooks/drive-mode.sh; do
  if [ -f "$E2E/$want" ]; then ok "install.sh placed $want"; else bad "install.sh placed $want"; fi
done
if [ -x "$E2E/hooks/drive-mode.sh" ]; then ok "the hook is executable"; else bad "the hook is executable"; fi
assert_json "$E2E/settings.json" "install.sh leaves valid JSON"
if settings_hook_registered "$E2E/settings.json" drive-mode.sh; then ok "install.sh registered the hook"; else bad "install.sh registered the hook"; fi
if ls "$E2E"/settings.json.bak.* >/dev/null 2>&1; then ok "install.sh wrote a backup"; else bad "install.sh wrote a backup"; fi
if [ "$HAVE_PY" = 1 ]; then
  assert_eq 'Bash(git status:*)' "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["permissions"]["allow"][0])' "$E2E/settings.json")" \
    "install.sh preserved an unrelated setting"
fi

CLAUDE_DIR="$E2E" bash "$ROOT/install.sh" > "$WORK/install2.log" 2>&1
if grep -q "already registered" "$WORK/install2.log"; then ok "a second install.sh is a no-op on settings.json"
else bad "a second install.sh is a no-op on settings.json" "$(cat "$WORK/install2.log")"; fi
if [ "$(ls "$E2E"/settings.json.bak.* | wc -l | tr -d ' ')" = 1 ]; then ok "the no-op install writes no second backup"
else bad "the no-op install writes no second backup"; fi

if CLAUDE_DIR="$E2E" bash "$ROOT/uninstall.sh" > "$WORK/uninstall.log" 2>&1; then
  ok "uninstall.sh exits clean"
else
  bad "uninstall.sh exits clean" "$(cat "$WORK/uninstall.log")"
fi
for gone in skills/drive/SKILL.md commands/drive-on.md commands/drive-off.md hooks/drive-mode.sh drive-mode; do
  if [ -e "$E2E/$gone" ]; then bad "uninstall.sh removed $gone"; else ok "uninstall.sh removed $gone"; fi
done
if [ "$(cat "$E2E/settings.json")" = "$(printf '%s' "$ORIGINAL")" ]; then
  ok "install then uninstall restores settings.json byte for byte"
else
  bad "install then uninstall restores settings.json byte for byte" "$(cat "$E2E/settings.json")"
fi

# A clean machine: no settings.json at all.
CLEAN="$WORK/clean"; mkdir -p "$CLEAN"
if CLAUDE_DIR="$CLEAN" bash "$ROOT/install.sh" > "$WORK/clean.log" 2>&1; then
  ok "install.sh works with no settings.json to start from"
else
  bad "install.sh works with no settings.json to start from" "$(cat "$WORK/clean.log")"
fi
assert_json "$CLEAN/settings.json" "the settings.json it creates is valid JSON"
if ls "$CLEAN"/settings.json.bak.* >/dev/null 2>&1; then
  bad "no backup is written for a file that did not exist"
else
  ok "no backup is written for a file that did not exist"
fi

# ---------------------------------------------------------------------------
group "Size budget"
# ---------------------------------------------------------------------------
BUDGET="$WORK/budget"; mkdir -p "$BUDGET"
FATREPO="$WORK/fatrepo"
mkdir -p "$FATREPO/skills/drive" "$FATREPO/commands" "$FATREPO/hooks"
cp "$ROOT/lib.sh" "$FATREPO/"; cp "$ROOT/install.sh" "$FATREPO/"
cp "$ROOT/commands/"*.md "$FATREPO/commands/"; cp "$ROOT/hooks/drive-mode.sh" "$FATREPO/hooks/"
{ printf -- '---\nname: drive\n---\n\n'; i=0; while [ $i -lt 200 ]; do printf 'padding line to blow the budget wide open %d\n' $i; i=$((i + 1)); done; } > "$FATREPO/skills/drive/SKILL.md"
if CLAUDE_DIR="$BUDGET" bash "$FATREPO/install.sh" > "$WORK/fat.log" 2>&1; then
  bad "install.sh refuses an over-budget contract"
else
  if grep -q "over the 9,000 budget" "$WORK/fat.log"; then ok "install.sh refuses an over-budget contract"
  else bad "install.sh refuses an over-budget contract" "$(cat "$WORK/fat.log")"; fi
fi
if [ -e "$BUDGET/skills/drive/SKILL.md" ]; then bad "the refused install copied nothing"; else ok "the refused install copied nothing"; fi

BODY="$(strip_frontmatter "$ROOT/skills/drive/SKILL.md")"
if [ "${#BODY}" -le 9000 ]; then ok "the shipped contract is inside the budget (${#BODY} chars)"
else bad "the shipped contract is inside the budget" "${#BODY} chars"; fi

# ---------------------------------------------------------------------------
group "OmniRoute deployment against a stub gateway"
# ---------------------------------------------------------------------------
STUB="$WORK/bin"; mkdir -p "$STUB"
cat > "$STUB/omniroute" <<'STUBEOF'
#!/bin/bash
# Stub OmniRoute CLI: stores a put payload, replays it on get, and surrounds the
# reply with the chatty notices the real CLI prints.
STORE="$OMNIROUTE_STUB_STORE"
case "$3" in
  put-api-settings-system-prompt) cp "${5#@}" "$STORE"; echo "ok" ;;
  get-api-settings-system-prompt)
    echo "note: using base url $OMNIROUTE_BASE_URL"
    cat "$STORE"
    echo
    echo "note: done" ;;
esac
STUBEOF
chmod +x "$STUB/omniroute"
export OMNIROUTE_STUB_STORE="$WORK/omni-store.json"
if PATH="$STUB:$PATH" bash "$ROOT/omniroute/install-omniroute.sh" > "$WORK/omni.log" 2>&1; then
  ok "install-omniroute.sh completes and verifies its own write"
else
  bad "install-omniroute.sh completes and verifies its own write" "$(cat "$WORK/omni.log")"
fi
assert_json "$OMNIROUTE_STUB_STORE" "the payload it sends is valid JSON"
if [ "$HAVE_PY" = 1 ]; then
  sent="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["prefixPrompt"])' "$OMNIROUTE_STUB_STORE")"
  body="$(strip_frontmatter "$ROOT/skills/drive/SKILL.md")"
  body="${body#"${body%%[![:space:]]*}"}"
  if [ "${sent#*$'\n\n'}" = "$body" ]; then
    ok "the contract arrives at the gateway byte-identical to SKILL.md"
  else
    bad "the contract arrives at the gateway byte-identical to SKILL.md"
  fi
  if python3 -c 'import json,sys;sys.exit(0 if json.load(open(sys.argv[1]))["enabled"] is True else 1)' "$OMNIROUTE_STUB_STORE"; then
    ok "the payload enables the prompt"
  else
    bad "the payload enables the prompt"
  fi
fi
# A gateway that truncates must be caught, not reported as success.
cat > "$STUB/omniroute" <<'STUBEOF'
#!/bin/bash
STORE="$OMNIROUTE_STUB_STORE"
case "$3" in
  put-api-settings-system-prompt) cp "${5#@}" "$STORE"; echo ok ;;
  get-api-settings-system-prompt) echo '{"enabled": true, "prefixPrompt": "truncated", "suffixPrompt": ""}' ;;
esac
STUBEOF
if PATH="$STUB:$PATH" bash "$ROOT/omniroute/install-omniroute.sh" > "$WORK/omni2.log" 2>&1; then
  bad "a truncated read-back is reported as a failure"
else
  if grep -q "lengths differ" "$WORK/omni2.log"; then ok "a truncated read-back is reported as a failure"
  else bad "a truncated read-back is reported as a failure" "$(cat "$WORK/omni2.log")"; fi
fi

# ---------------------------------------------------------------------------
printf '\n%s\n' "-----------------------------------------------"
printf '%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
