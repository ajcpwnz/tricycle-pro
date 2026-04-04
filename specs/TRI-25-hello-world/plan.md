# Implementation Plan: Hello World Command

**Branch**: `TRI-25-hello-world` | **Date**: 2026-04-04 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/TRI-25-hello-world/spec.md`
**Version**: 0.12.0 → 0.13.0 (minor bump — new feature)

## Summary

Add a `hello-world` command to the tricycle CLI that prints "Hello, world!" to stdout and exits with code 0. Implementation follows the existing bash function + case dispatcher pattern in `bin/tricycle`.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default)
**Primary Dependencies**: None new
**Storage**: N/A
**Testing**: Node.js built-in `node:test` via `execSync`
**Target Platform**: macOS / Linux CLI
**Project Type**: CLI tool
**Performance Goals**: Sub-second execution
**Constraints**: Bash 3.2 compatibility (macOS default)
**Scale/Scope**: Single command addition, minimal surface area

## Constitution Check

*GATE: Constitution is unpopulated — no gates to enforce.*

No violations. Proceeding.

## Project Structure

### Documentation (this feature)

```text
specs/TRI-25-hello-world/
├── spec.md
├── plan.md              # This file
├── research.md
└── checklists/
    └── requirements.md
```

### Source Code (changes to existing files + 1 new test)

```text
bin/
└── tricycle              # Add cmd_hello_world() function + case entry + help text

tests/
└── test-hello-world.js   # New test file for the command
```

**Structure Decision**: No new directories needed. The command is a function added to the existing monolithic CLI script, following the established pattern.

## Implementation Details

### 1. Add `cmd_hello_world()` function to `bin/tricycle`

Place the function near the other `cmd_*` functions. Pattern:

```bash
cmd_hello_world() {
  echo "Hello, world!"
}
```

### 2. Register in case dispatcher

Add `hello-world` case entry in the dispatch block at the end of `bin/tricycle`:

```bash
hello-world) cmd_hello_world ;;
```

### 3. Update help text

Add `hello-world` to the usage/help output so it appears when running `tricycle --help`.

### 4. Add test file `tests/test-hello-world.js`

Test using the established Node.js pattern:
- Invoke `bin/tricycle hello-world` via `execSync`
- Assert stdout is exactly `"Hello, world!\n"`
- Assert exit code is 0
- Test with extra arguments to verify they are ignored

### 5. Version bump

Update `VERSION` from `0.12.0` to `0.13.0` (new feature = minor bump).

## Complexity Tracking

No constitution violations. No complexity to justify.
