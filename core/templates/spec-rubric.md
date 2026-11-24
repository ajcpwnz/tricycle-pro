# Spec rubric

The writer of a spec and the `trc-spec-validator` agent use this one rubric. A
spec tells the implementer what to build and why. It is not an edit script. The
implementer reads the code and makes the small choices.

## Blocker

A blocker fails the spec. A finding is a blocker only when building the spec as
written breaks the app or the feature. There are four kinds:

1. **Wrong base:** the design depends on a behavior, file, function, key or API
   that does not exist or does not work as the spec says. Example: the spec
   extends a function that the code does not call.
2. **Missed copy that breaks:** a copy of the changed text or behavior that the
   spec does not name, and that makes the app or the feature fail if it stays
   unchanged. Example: a second parser of the same config key.
3. **Broken rule:** the solution conflicts with `CLAUDE.md`, the constitution or
   the rules of the app.
4. **Open question:** a choice that only the user can make is not settled, or
   the Open Questions section is not empty.

## Handoff

All else is a handoff: the implementer finds the solution during the work.
Examples:

- A `path:line` that is off, or that points to a generated file.
- A copy that the spec does not name, when a test or the mirror check finds it.
- An implementation choice: a variable name, the file of a test, the position
  of text in a doc.
- A checklist line with a weak proof, or an outcome with no line.
- A claim that the validator cannot check from the repository.

When a finding is between the two, it is a handoff.

## Writer checks

Do each check on the draft, with tools. Do not do it from memory.

1. **Base:** read each `path:line` that the design depends on, with `sed -n` or
   `grep -n`. Cite source files, not generated files: cite a block, not the
   command that the assembler makes from it.
2. **Copies:** for each text or behavior that the solution changes, search the
   repository with `grep -rn`. Name each copy, or say which command regenerates
   it.
3. **Coverage:** each outcome of the solution has a checklist line. The proof
   is a test name, a command with its expected result, or an observed behavior.
   Do not write a grep proof for each sentence of a doc.

## Size

Analysis plus Proposed Solution: about 400 words for a feature, less for a fix.
Name the files and the behavior. Do not write the edits.
