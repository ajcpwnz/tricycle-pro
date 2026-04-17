# Contract: `derive-branch-name.sh`

**Status**: New script — `core/scripts/bash/derive-branch-name.sh`. Pure slug/branch derivation extracted from `create-new-feature.sh`.

## Purpose

Print the branch name that would be produced for a given feature description + branching-style configuration, without creating any branch, worktree, spec directory, or side effect. Used by both:

- `create-new-feature.sh` (existing), which now sources it for slug logic.
- `.claude/hooks/rename-on-kickoff.sh` (new), which calls it to compute the session label.

## Invocation

```
derive-branch-name.sh --style <style> [--prefix <prefix>] [--issue <id>] --short-name <slug> <feature_description>
```

Flags mirror `create-new-feature.sh`. `--style` is required; all other semantics identical to the existing script.

## Exit codes

- `0` — success; branch name printed to stdout on a single line.
- `2` — `--style issue-number` requested but no `--issue` supplied and the description contains no matching `<PREFIX>-<NUM>` pattern. (Same code `create-new-feature.sh` returns for this case today.)
- `1` — any other invocation error (missing `--short-name`, missing description, etc.).

## Stdout format

Exactly one line: the branch name. No newline padding beyond a single trailing `\n`. No JSON — this helper is a pure derivation, callers that need JSON wrap it.

## Absence of side effects

The helper MUST NOT:

- Touch `specs/`, `.trc/`, or any file under the repo.
- Call `git` other than read-only operations if ever needed (none today).
- Read `tricycle.config.yml` — callers pass style/prefix as flags.
- Prompt the user or write to stderr for anything other than errors.

## Compatibility

`create-new-feature.sh` MUST continue to accept every flag combination it accepts today and produce the same branch name for the same inputs — this refactor is behavior-preserving. A test pins the parity.

---

# Contract: `.claude/hooks/rename-on-kickoff.sh`

**Status**: New hook — installed by `tricycle generate settings` under the `UserPromptSubmit` event.

## Trigger

Fires on every `UserPromptSubmit` event. Parses the prompt text and acts only when the first non-whitespace token is one of `/trc.specify`, `/trc.headless`, `/trc.chain`. For any other prompt it's a silent no-op (empty stdout, exit 0).

## Input

Standard Claude Code hook input on stdin — a JSON object with at minimum `prompt` (the user's submitted text) and the session context fields the host provides.

## Output

On match, a JSON object on stdout:

```json
{
  "hookSpecificOutput": {
    "sessionTitle": "<computed label>"
  }
}
```

On no match or on derivation error, empty stdout + exit 0. The hook never blocks the prompt — if derivation fails, Claude Code still sees the user's prompt and the command template's fallback `/rename` instruction kicks in.

## Derivation

- For `/trc.specify` and `/trc.headless`: parses the argument string, reads `branching.style` and `branching.prefix` from `tricycle.config.yml`, calls `.trc/scripts/bash/derive-branch-name.sh` with matching flags. If `issue-number` style is configured but no ticket ID is present in the argument string, the hook emits empty stdout (no rename yet) — the command template will rename later once it has the ID.
- For `/trc.chain`: parses the range-or-list argument, computes the chain-scoped label per `data-model.md` rules, does NOT call `derive-branch-name.sh`.

## Idempotency

Before emitting, reads `$CLAUDE_SESSION_TITLE` (or the host-exposed current-label env var). If equal to the computed target, emits empty stdout.

## Time budget

< 500 ms on cold cache. This is a pre-prompt hook; it runs on every user message, so non-matching invocations must return in < 10 ms.

## Registration

`tricycle generate settings` adds a `UserPromptSubmit` hook entry pointing at `.claude/hooks/rename-on-kickoff.sh`. The hook is always registered when the workflow.chain includes any of the three kickoff commands (which in practice is "always" — the default chain).

---

# Contract: Command-template fallback instruction

**Status**: Addition to `core/commands/trc.specify.md`, `core/commands/trc.headless.md`, `core/commands/trc.chain.md`.

Each command template gains a new Step 0.5: **Session rename (fallback)**. This step runs only if the UserPromptSubmit hook did not already rename the session.

Detection: read `$CLAUDE_SESSION_TITLE` (or the host-equivalent); if it differs from the derived target, the agent emits an instruction to invoke `/rename <target>` as its first user-facing action, and then proceeds. If the label already matches, skip.

This fallback exists only for hosts that don't honor `hookSpecificOutput.sessionTitle` (older Claude Code versions) or installs where the hook isn't yet registered (consumer ran `tricycle init` before this feature landed and hasn't run `tricycle update` yet).
