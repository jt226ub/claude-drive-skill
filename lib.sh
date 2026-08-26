#!/bin/bash
# Shared helpers for install.sh and uninstall.sh. Not installed anywhere —
# those two scripts are the only consumers.

# Echo the name of a JSON-capable runtime, or return 1 if there is none.
#
# The probe RUNS the interpreter rather than merely locating it. Windows puts
# python/python3 App Execution Alias shims on PATH that `command -v` resolves
# happily and that then exit 49 without executing anything, printing a "install
# from the Microsoft Store" notice instead. Trusting PATH would reintroduce the
# exact silent-dependency failure that got jq removed in the first place.
#
# node first because it preserves object key order, so a hand-maintained
# settings.json comes back out in the order its author left it. perl second:
# JSON::PP has been core since 5.14, which covers macOS, essentially every
# Linux, and Git for Windows — the broadest reach of anything here — at the
# cost of alphabetising keys on the way out. python is deliberately not in the
# list; its Windows shim makes it the least trustworthy of the three, and
# node plus perl already cover the ground.
json_runtime() {
  if command -v node >/dev/null 2>&1 && node -e 'JSON.parse("{}")' >/dev/null 2>&1; then
    echo node
    return 0
  fi
  if command -v perl >/dev/null 2>&1 && perl -MJSON::PP -e 'decode_json("{}")' >/dev/null 2>&1; then
    echo perl
    return 0
  fi
  return 1
}

# Escape a string for use inside a JSON string literal (quotes not included).
# Covers backslash and double quote, which is the whole realistic surface for a
# filesystem path; a path containing raw control characters is not supported.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
