---
description: Create the project constitution, or amend one principle of it, and keep the references to it true.
---

## User Input

```text
$ARGUMENTS
```

## Constitution

The constitution lives at `constitution.root` in `tricycle.config.yml` (default
`.trc/memory/constitution.md`). The validator, `/trc.plan` and `/trc.implement` read
it. It is the project's list of rules that the code must follow.

### Create

Use this when the file is missing, holds only the line that `tricycle init` writes
(`Run /trc.constitution to populate this file.`), or still holds the `[PLACEHOLDER]`
tokens of `.trc/templates/constitution-template.md`.

1. Read the user input, `CLAUDE.md`, the README and the code. Derive the rules that
   the project already follows or that the user asks for.
2. Write one section per principle: a short name, then the rule. Use MUST or NEVER,
   so a reviewer can check the rule against the code. Add the reason when the rule
   does not explain itself.
3. Set the version to `1.0.0` and both dates to today.

### Amend

Use this when the file already holds real principles.

1. Change only what the user asks for. Keep every other line exactly as it is.
2. Read the other principles. If the change conflicts with one of them, ask the user
   with `AskUserQuestion` before you write.
3. Bump the version. MAJOR removes or redefines a principle. MINOR adds a principle or
   widens one. PATCH changes only the wording. Set `Last Amended` to today.

### Keep references true

Search `CLAUDE.md`, `AGENTS.md` and `.trc/blocks/custom/` for the name or number of
each changed principle. Fix each reference that the change made false. Do not
create any other file.

### Report

State the old and the new version, the principles that changed, the references
that you fixed, and a one-line commit message.
