# LLM Drive Skill

**drive** is an operating contract for substantive work. It targets six failure
modes: turns that end with unannounced undone work, "done" that was never run,
patches over symptoms, silent scope drift, multi-step jobs with no visible
state, and answers that bury the outcome.

The contract is harness-agnostic — it names no vendor, no tool, and no slash
command — so the same text drives Claude Code and any other model you can put a
system prompt in front of. It ships two ways:

| | Claude Code (`install.sh`) | Any LLM, via a gateway (`omniroute/install-omniroute.sh`) |
| --- | --- | --- |
| Reaches | Claude Code on this machine | every client and model through the gateway |
| Mechanism | a `UserPromptSubmit` hook, plus a `/drive` skill | `prefixPrompt`, prepended to the system prompt |
| Toggle | `/drive-on` and `/drive-off` | always on; no client can opt out |
| Needs | bash | bash, and the gateway's own CLI |

`skills/drive/SKILL.md` is the single source of truth for both. Neither
installer edits it; both strip its YAML frontmatter with the same rule and ship
the body verbatim, and the test suite asserts the two paths produce
byte-identical text.

## Install for Claude Code

```bash
git clone https://github.com/jt226ub/llm-drive-skill.git
cd llm-drive-skill
./install.sh
```

Restart Claude Code, then run `/drive-on` to switch on the standing mode.
Install alone does not enable it — it only puts the parts in place.

To let a Claude Code session do it for you, point it at the repo:

> Clone https://github.com/jt226ub/llm-drive-skill and run ./install.sh

It works two ways once installed:

- **`/drive`** — apply the contract to one task, on demand.
- **`/drive-on`** — standing mode. A `UserPromptSubmit` hook injects the
  contract into *every* prompt, in every session, until `/drive-off`.

### What gets installed

Four parts, all under `~/.claude` — the skill is the only one that holds
content; the rest are plumbing.

| File | Role |
| --- | --- |
| `skills/drive/SKILL.md` | The contract itself — **single source of truth**. |
| `commands/drive-on.md` | `/drive-on` — creates the `~/.claude/drive-mode` flag. |
| `commands/drive-off.md` | `/drive-off` — removes the flag. |
| `hooks/drive-mode.sh` | On each prompt, if the flag exists, injects the contract. |

`install.sh` also registers the hook under `hooks.UserPromptSubmit` in
`~/.claude/settings.json`. It backs the file up first, merges rather than
overwrites, and skips the edit entirely if the hook is already registered, so
re-running is safe and other hooks survive.

## Install for any other LLM

```bash
./omniroute/install-omniroute.sh
```

Ships the same contract into [OmniRoute](https://github.com/diegosouzapw/OmniRoute)'s
Global System Prompt, so every client and model routed through the gateway
receives it. See [omniroute/README.md](omniroute/README.md) for the base-URL and
CLI options, and for a measured note on which providers hold up under the added
context.

Any other gateway or client that accepts a system prompt works the same way:
take the body of `skills/drive/SKILL.md` below its frontmatter and prepend it.
Nothing in the contract depends on Claude Code, on tools being available, or on
slash commands existing.

## No dependencies

Nothing here needs jq, node, perl, python, awk or sed. The floor is `bash` and
the coreutils that come with it.

That is a deliberate correction, not a boast. The hook originally built a JSON
`additionalContext` envelope with `jq`. `jq` is absent on most Windows machines,
and its absence was **silent**: the broken pipeline still let the script
`exit 0`, so drive mode never engaged and never said why. Several installs hit
that and had to work around it.

The first fix tiered `node`, then `perl`, then a paste-this-yourself fallback.
That narrowed the problem instead of solving it — `node` is not on `PATH` when
Claude Code is installed as a native binary, `perl` is missing from minimal
containers, and Windows ships `python`/`python3` App Execution Alias shims that
satisfy `command -v` and then exit without running anything.

So the JSON handling moved into bash. `lib.sh` holds a scanner that locates and
rewrites members of `settings.json` in place; every other byte — key order,
indentation, whatever you hand-wrote — is left exactly as it was. The hook runs
no subprocess at all.

| Situation | What happens |
| --- | --- |
| No `settings.json`, or an empty one | Created, then registered into. |
| Hook already registered | Left alone; no backup written. |
| Existing content | Merged into, backup written first. |
| Not valid JSON, or `hooks` is not an object | Refused and left untouched; the snippet is printed to paste. |

Honest limits, all covered by the test suite:

- A **minified** `settings.json` comes back valid but mixed-format — the
  inserted block is indented, the rest stays on one line.
- Editing scales linearly with file size: about **0.15 s** for a typical 3.5 KB
  `settings.json`, **2.4 s** for a 30 KB one. Chunked indexing is what keeps
  that linear; reading the document character by character made it quadratic,
  and a 100 KB file took nine seconds.
- Keys written with `\u` escapes are compared raw and so will not match. Real
  `settings.json` keys are plain ASCII.
- Setting `CLAUDE_DIR` to something other than `~/.claude` installs the files
  there, but the hook and the two slash commands still read the flag and the
  skill from `$HOME/.claude`. `install.sh` says so when you do it.

## Checking a machine

Rolling this out to a second machine raises an obvious question — is drive mode
actually running there, and on which contract? Both answers are one line, and
both should be asked of *behaviour*, not of the source text:

```bash
# Is the standing mode actually injecting anything?
bash ~/.claude/hooks/drive-mode.sh | head -1

# Which contract is installed?
grep -q 'Harness-agnostic' ~/.claude/skills/drive/SKILL.md && echo current || echo pre-1.5
```

A working install prints `DRIVE MODE IS ON …`. Silence means one of two things:
the flag is simply off (check that `~/.claude/drive-mode` exists — `/drive-on`
creates it), or the hook is broken. **The broken case is silent by design**, and
it is the one that motivated all of this: the old hook piped through `jq`,
and where `jq` was missing the pipeline failed while the script still exited 0
— so drive mode injected nothing and said nothing about it. Measured on an old
install with `jq` off `PATH`: 0 bytes emitted, exit code 0. The current hook
emits the full contract with `PATH` empty entirely.

Do **not** try to tell the versions apart by grepping the hook for `jq`. The
current hook names `jq` in a comment explaining why it no longer uses it, so
`grep -c jq` returns 1 for both the old and the new script. Run the hook
instead.

## Tests

```bash
./tests/run-tests.sh
```

107 assertions. A JSON editor written by hand is only defensible against
evidence, so the suite covers the shapes a real `settings.json` takes — no
`hooks` key, `hooks` without `UserPromptSubmit`, an existing foreign entry,
minified, tab-indented, unicode and quoted prose — and asserts valid JSON out,
unrelated settings preserved, a full install/uninstall round trip that restores
the file byte for byte, and a refusal that leaves a malformed file untouched
rather than guessing.

It also asserts the two copies of the frontmatter rule stay byte-identical, that
no shipped script invokes any of the tools listed above, and that the hook still
emits the whole contract with `PATH` set to nothing at all — a direct regression
guard on the silent failure described above. Verified on bash 3.2.57, the
version macOS ships as `/bin/bash`; newer bash is untested here.

`python3` is used for independent JSON validation when present. It is a
developer convenience only — nothing in the installed product needs it — and
those checks report `skip` rather than passing quietly when it is missing.

## Editing the contract

Edit `skills/drive/SKILL.md` and nothing else.

**Size budget:** both installers refuse a contract body over 9,000 characters.
In standing mode the whole body rides on *every* prompt, so its length is a cost
paid per turn. The number is self-imposed: it was originally a guard against a
10,000-character `additionalContext` cap the stdout path no longer goes
through, and OmniRoute would accept 50,000 — but one `SKILL.md` has to fit both
targets, and the per-turn cost was always the better reason to keep the contract
tight. It currently runs 7,168 characters.

## Removing it

```bash
./uninstall.sh
```

Deletes the four files and the flag, and deregisters the hook from
`settings.json` (backup written). It removes only the entry naming
`drive-mode.sh`, leaving other `UserPromptSubmit` hooks in place, and drops the
`hooks` key only if that emptied it. Earlier backups are left behind
deliberately.

## Where it helps, where it costs

Worth it for multi-step engineering work, where the discipline pays for itself
in verified finishes. Pure overhead for quick questions and chat — the standing
mode spends context on every prompt regardless of the task, which is why
`/drive-off` and the one-shot `/drive` both exist. The gateway deployment has no
such escape hatch by design, which is the trade it makes for reaching
everything.
