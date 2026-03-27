# Implementation Plan: Fix Template Engine Awk Syntax Error

**Branch**: `TRI-8-fix-template-engine` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)
**Version**: 0.8.0 → 0.8.1 (patch bump — bug fix)

## Summary

Fix the awk syntax error in `process_if_blocks()` caused by using `close` (an awk built-in function name) as a variable name. Also fix related regex issues where `sub()` is used with template tag patterns containing awk regex metacharacters. Add test coverage for `generate claude-md` across all presets.

## Technical Context

**Language/Version**: Bash, awk (POSIX/nawk on macOS)
**File to fix**: `bin/lib/template_engine.sh`
**Project Type**: CLI tool (pure bash)

## Constitution Check

N/A — constitution not populated.

## Project Structure

```text
bin/lib/
└── template_engine.sh        # Fix: rename awk variable, fix sub() regex issues

tests/
└── run-tests.sh              # Add: generate claude-md tests for all presets
```

## Design Decisions

### D1: Rename `close` → `ctag` in awk
Avoids conflict with POSIX awk built-in `close()`.

### D2: Replace `sub()` with `index()` + `substr()` for literal string removal
`sub()` treats its first argument as regex. Template tags like `{{#if key}}` contain `{` which is a regex quantifier. Using `index()` for finding and `substr()` for extraction avoids regex interpretation entirely.

## Implementation Approach

1. In `process_if_blocks()`: rename `-v close=` to `-v ctag=` and update all awk references
2. In the awk script: replace `sub(open ".*", "", before)` with `index()` + `substr()` based literal removal — same for `close` tag removal
3. Add test: `generate claude-md` succeeds for all presets (no stderr errors, output contains project name)
4. Version bump 0.8.0 → 0.8.1
