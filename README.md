# drive — a completion-discipline skill for Claude Code

An operating contract for Claude Code that targets six failure modes: turns
that end with unannounced undone work, "done" that was never run, patches over
symptoms, silent scope drift, multi-step jobs with no visible state, and
answers that bury the outcome.

It works two ways:

- **`/drive`** — apply the contract to one task, on demand.
- **`/drive-on`** — standing mode. A `UserPromptSubmit` hook injects the
  contract into *every* prompt, in every session, until `/drive-off`.

## Install on another machine

```bash
git clone https://github.com/jt226ub/claude-drive-skill.git
cd claude-drive-skill
./install.sh
```

Restart Claude Code, then run `/drive-on` to switch on the standing mode.
Install alone does not enable it — it only puts the parts in place.

Needs `bash` and `awk`, and nothing else on a machine with no `settings.json`
yet. See [No jq](#no-jq) for the one case that wants more.

To let a Claude Code session do it for you, point it at the repo:

> Clone https://github.com/jt226ub/claude-drive-skill and run ./install.sh

## What gets installed

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

## No jq

The hook writes the contract to plain stdout, which `UserPromptSubmit` adds to
the turn's context. It previously built a JSON `additionalContext` envelope
with `jq` — which is absent on most Windows machines, and since the broken
pipeline still let the script `exit 0`, drive mode just quietly never engaged.
A dependency whose absence is silent is worse than one that fails loudly, so it
went.

Editing an existing `settings.json` is the one job that still wants a real JSON
parser, and `install.sh` handles it in tiers:

| Situation | What happens |
| --- | --- |
| No `settings.json`, or an empty one | The file is written whole. No parser needed. |
| Hook already registered | Left alone. |
| Existing content, `node` or `perl` runs | Merged with it, backup written first. |
| Existing content, neither runs | File untouched; the snippet is printed to paste. |

`node` is preferred because it preserves key order; `perl` is the fallback
because `JSON::PP` has been core since 5.14, which covers macOS, essentially
every Linux, and Git for Windows — at the cost of alphabetising the keys it
writes back. `python` is deliberately not used: Windows ships
`python`/`python3` App Execution Alias shims that satisfy `command -v` and then
exit 49 without running anything, so detection here probes by *executing* the
interpreter rather than by finding it on `PATH`.

`uninstall.sh` deregisters the hook the same way, and when no runtime is
available it says so and leaves the entry in place — harmless, since it points
at a script that has just been deleted.

## Editing the contract

Edit `skills/drive/SKILL.md` and nothing else. The hook strips the YAML
frontmatter and injects the body verbatim, so the `/drive` skill and the
standing mode can never drift apart.

**Size budget:** `install.sh` refuses to install a contract body over 9,000
characters and tells you to trim. In standing mode the whole body is injected
into *every* prompt, so its length is a cost paid on each turn. The 9,000 is a
self-imposed budget — it was originally the guard against a 10,000-character
`additionalContext` cap, which the stdout path no longer goes through, but the
context cost was always the better reason to keep the contract tight.

## Removing it

```bash
./uninstall.sh
```

Deletes the four files and the flag, and deregisters the hook from
`settings.json` (backup written). Backups are left behind deliberately.

## Where it helps, where it costs

Worth it for multi-step engineering work, where the discipline pays for itself
in verified finishes. Pure overhead for quick questions and chat — the standing
mode spends context on every prompt regardless of the task, which is the reason
`/drive-off` and the one-shot `/drive` both exist.
