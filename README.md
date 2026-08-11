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

Requires `jq` (`brew install jq` / `apt install jq`), which the hook uses to
build its JSON output.

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

## Editing the contract

Edit `skills/drive/SKILL.md` and nothing else. The hook strips the YAML
frontmatter and injects the body verbatim, so the `/drive` skill and the
standing mode can never drift apart.

**Size limit:** the harness caps injected `additionalContext` at 10,000
characters. `install.sh` refuses to install a body over 9,000 and tells you to
trim; without that guard the contract would be silently truncated mid-sentence.

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
