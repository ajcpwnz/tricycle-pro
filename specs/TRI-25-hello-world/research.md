# Research: Hello World Command

## Command Registration Pattern

**Decision**: Add a `cmd_hello_world()` bash function to `bin/tricycle` and register it in the `case` dispatcher.

**Rationale**: All existing commands follow this exact pattern — bash function + case entry. No framework, no plugin system. The simplest approach is to follow the established convention.

**Alternatives considered**:
- External script in `bin/lib/` — rejected; all current commands are inline functions in the main script.
- Node.js command — rejected; the CLI is entirely bash-based.

## Testing Approach

**Decision**: Add a Node.js test file (`tests/test-hello-world.js`) using the `node:test` built-in module, invoking the CLI via `execSync` and asserting stdout output and exit code.

**Rationale**: Existing tests use `node:test` with `execSync` to invoke bash scripts and check output. This is the established pattern.

**Alternatives considered**:
- Pure bash test — rejected; the project already standardized on Node.js test runner.
- Inline in existing test file — rejected; each feature area has its own test file.

## Help Text

**Decision**: Add `hello-world` to the help/usage output in the CLI.

**Rationale**: All existing commands appear in help text. Omitting it would be inconsistent.
