# Research: TRI-8 Fix Template Engine

**Date**: 2026-03-28
**Branch**: TRI-8-fix-template-engine

## Decision 1: Root Cause — `close` is an awk built-in

**Decision**: Rename awk variable `close` to `ctag` in `process_if_blocks()`.

**Rationale**: `close` is a POSIX awk built-in function (closes files and pipes). macOS ships with nawk which treats `close` as a reserved word. Using it as a variable via `-v close="..."` causes a syntax error when referenced as `index($0, close)` — nawk tries to parse it as a function call.

GNU awk (gawk) is more permissive and may allow shadowing built-ins, which is why this bug may not reproduce on all systems.

**Fix**: Change `-v close="$close_tag"` to `-v ctag="$close_tag"` and update all references inside the awk script.

**Alternatives considered**:
- Escape the variable differently: Not possible — it's an awk parsing issue, not a quoting issue
- Switch to sed: Would add complexity for multiline block removal
- Require gawk: Would add an external dependency — violates project constraints

## Decision 2: Additional Rendering Issues

**Decision**: Audit the entire `render_template()` function for related issues while fixing the awk bug.

**Rationale**: The bug report mentions "lines concatenated without newlines" and "empty sections." The awk fix alone may not resolve all rendering issues. The `printf "%s"` calls in the awk script may drop newlines, and the `sub()` calls use the tag values as regex patterns — `{{` contains regex metacharacters.

**Known secondary issues**:
1. `sub(open ".*", "", before)` on line 120 — `open` contains `{{#if key}}` which has `{` regex quantifiers. Should use `index()` + `substr()` instead of `sub()` for literal string removal.
2. `sub(".*" close, "", after)` on lines 127, 138 — same regex issue with `close_tag` containing `{{/if}}`.
