# Quickstart: TRI-24 Feature Status Command

## Files to create/modify

| Action | File                    | Purpose                          |
|--------|-------------------------|----------------------------------|
| Create | `bin/lib/status.sh`     | Core status logic (scan, detect, format) |
| Modify | `bin/tricycle`          | Add `status` to command dispatch + help text |
| Create | `tests/test-status.js`  | Node.js tests for status logic   |
| Modify | `tests/run-tests.sh`    | Add status command integration tests |

## Implementation order

1. `bin/lib/status.sh` — the self-contained status module
2. Wire into `bin/tricycle` — dispatch + help
3. Tests — both Node.js unit and shell integration
4. Manual verification against real `specs/` directory
