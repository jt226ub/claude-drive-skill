# OmniRoute deployment

Ships the drive contract into [OmniRoute](https://github.com/diegosouzapw/OmniRoute)'s
**Global System Prompt** instead of a Claude Code hook.

```bash
./omniroute/install-omniroute.sh
```

`skills/drive/SKILL.md` remains the single source of truth. This script never edits the
contract — it strips the YAML frontmatter with the same `awk` rule `hooks/drive-mode.sh`
uses, so both deployment paths inject byte-identical text.

## Why server-side

| | Claude Code hook (`install.sh`) | OmniRoute (`install-omniroute.sh`) |
|---|---|---|
| Scope | Claude Code only | every client and model through the gateway |
| Toggle | `/drive-on` / `/drive-off` | always on; no client can opt out |
| Mechanism | `UserPromptSubmit` → `additionalContext` | `prefixPrompt` prepended to system content |
| Size ceiling | 10,000 chars (hard truncation) | 50,000 chars |

The hook only reaches Claude Code, and any client can switch it off. Injecting at the
gateway is the only placement that is genuinely always-on across every model, which is
why this branch exists.

## Why the contract in this branch is harness-agnostic

The previous expanded draft referenced `~/.claude/drive-mode`, `UserPromptSubmit`, and
six slash commands. Those are meaningless to a model reached through a gateway — there
are no slash commands on that path — so they were removed. Two guards were added that a
gateway deployment needs and a hook deployment does not:

- **Proportion** — the contract now hits *every* request, including one-line questions.
  Without an explicit instruction to scale effort to the task, a trivial ask gets the
  full ceremony. Verified: "What is the capital of France?" returns `Paris.`
- **Capability** — a gateway request may have no test runner, no filesystem, no tools at
  all. The contract tells the model to apply a rule's intent and state plainly what it
  could not verify, rather than fabricate having run something.

## Size limit

The script enforces the 9,000-char guard from `install.sh` even though OmniRoute would
accept up to 50,000. This is deliberate: one `SKILL.md` must stay deployable to *both*
targets. Letting it grow past 9,000 to suit the gateway would silently truncate the tail
on the Claude Code path — losing whatever sits at the end of the file, with no warning.

## Known interaction: emulated tool calling

OmniRoute's web-cookie providers (`deepseek-web`, `chatgpt-web`, …) have no native
function calling. Tools are serialised into the system prompt and the model's
`<tool>{...}</tool>` text is parsed back out
(`open-sse/translator/webTools.ts`). Adherence to that envelope is therefore
model-dependent, and a malformed block is returned as **visible text** rather than
executed.

Measured on an identical 11-tool-call task through OmniRoute:

- `ds-web/deepseek-chat` — completed cleanly, every call parsed
- `ds-web/deepseek-v4-pro` — emitted pseudo-XML (`<name="read">`) that the parser
  rejected, and leaked the protocol's `_nonce` field into tool arguments

Prefer a model with demonstrated envelope adherence for agentic work. This is a property
of the provider path, not of this contract — but injecting ~1,800 tokens of contract adds
context pressure, so it is worth knowing which model you are driving.

## Merge intent

`skills/drive/SKILL.md` on this branch is the merge candidate for `main`. It is already
harness-agnostic, fits both size ceilings, and needs no OmniRoute-specific edits — merging
it replaces the contract for the hook path too. The `omniroute/` directory is additive and
does not affect `install.sh`.
