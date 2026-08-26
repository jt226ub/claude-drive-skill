# OmniRoute deployment

Ships the drive contract into [OmniRoute](https://github.com/diegosouzapw/OmniRoute)'s
**Global System Prompt**, rather than into a Claude Code hook.

```bash
./omniroute/install-omniroute.sh
```

```bash
OMNIROUTE_BASE_URL=http://host:20128 ./omniroute/install-omniroute.sh
OMNIROUTE_CLI=/path/to/OmniRoute/bin/omniroute.mjs ./omniroute/install-omniroute.sh
```

`skills/drive/SKILL.md` remains the single source of truth. This script never
edits the contract — it strips the YAML frontmatter with the same rule
`hooks/drive-mode.sh` uses, so both deployment paths ship byte-identical text.

## Why server-side

| | Claude Code hook (`install.sh`) | OmniRoute (`install-omniroute.sh`) |
|---|---|---|
| Scope | Claude Code only | every client and model through the gateway |
| Toggle | `/drive-on` / `/drive-off` | always on; no client can opt out |
| Mechanism | `UserPromptSubmit` → stdout | `prefixPrompt` prepended to system content |
| Size ceiling | none; a 9,000-char budget is self-imposed | 50,000 chars |

The hook only reaches Claude Code, and any client can switch it off. Injecting
at the gateway is the only placement that is genuinely always-on across every
model, which is why this path exists.

## Why the contract is harness-agnostic

An earlier draft referenced `~/.claude/drive-mode`, `UserPromptSubmit`, and six
slash commands. Those are meaningless to a model reached through a gateway —
there are no slash commands on that path — so they went. Two guards were added
that a gateway deployment needs and a hook deployment does not:

- **Proportion** — the contract now hits *every* request, including one-line
  questions. Without an explicit instruction to scale effort to the task, a
  trivial ask gets the full ceremony. Verified: "What is the capital of France?"
  returns `Paris.`
- **Capability** — a gateway request may have no test runner, no filesystem, no
  tools at all. The contract tells the model to apply a rule's intent and state
  plainly what it could not verify, rather than fabricate having run something.

That rewrite is what made one contract serve both targets, and it is now the
only contract in the repo.

## Size limit

The script enforces the same 9,000-character budget `install.sh` does, even
though OmniRoute would accept 50,000. One `SKILL.md` has to stay deployable to
*both* targets; letting it grow to suit the gateway would put a per-turn context
cost on every Claude Code prompt for text only the gateway needs.

## Dependencies

The `omniroute` CLI, and bash. The script used to shell out to `python3` to
build its JSON payload and parse the read-back; both are pure bash now, so it
needs nothing the gateway did not already require. (`node` appears only as the
interpreter for OmniRoute's own CLI when you point at it with `OMNIROUTE_CLI`.)

## Verifying the write

The script reads the prompt back and compares the stored encoded length against
what it sent, refusing to report success on an unverified write. Equal lengths
are the check that matters — a gateway that truncated the contract comes back
short. A gateway that merely *re-encodes* it (`\/` for `/`, `—` for an em
dash) would also differ, so a mismatch is reported as a warning pointing at the
dashboard rather than as proof of damage.

## Known interaction: emulated tool calling

OmniRoute's web-cookie providers (`deepseek-web`, `chatgpt-web`, …) have no
native function calling. Tools are serialised into the system prompt and the
model's `<tool>{...}</tool>` text is parsed back out
(`open-sse/translator/webTools.ts`). Adherence to that envelope is therefore
model-dependent, and a malformed block is returned as **visible text** rather
than executed.

Measured on an identical 11-tool-call task through OmniRoute:

- `ds-web/deepseek-chat` — completed cleanly, every call parsed
- `ds-web/deepseek-v4-pro` — emitted pseudo-XML (`<name="read">`) that the parser
  rejected, and leaked the protocol's `_nonce` field into tool arguments

Prefer a model with demonstrated envelope adherence for agentic work. This is a
property of the provider path, not of this contract — but injecting ~1,800
tokens of contract adds context pressure, so it is worth knowing which model you
are driving.
