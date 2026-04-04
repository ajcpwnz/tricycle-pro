# Tasks: Hello World Command

**Branch**: `TRI-25-hello-world` | **Plan**: [plan.md](plan.md)

## Phase 1: Tests

- [x] **T1**: Create test file `tests/test-hello-world.js` with tests for:
  - Command outputs exactly "Hello, world!\n" to stdout
  - Command exits with code 0
  - Extra arguments are ignored
  - **Files**: `tests/test-hello-world.js`

## Phase 2: Core Implementation

- [x] **T2**: Add `cmd_hello_world()` function to `bin/tricycle`
  - **Depends on**: T1
  - **Files**: `bin/tricycle`

- [x] **T3**: Register `hello-world` in the case dispatcher in `bin/tricycle`
  - **Depends on**: T2
  - **Files**: `bin/tricycle`

- [x] **T4**: Add `hello-world` to help/usage text in `bin/tricycle`
  - **Depends on**: T2 [P]
  - **Files**: `bin/tricycle`

## Phase 3: Polish

- [x] **T5**: Bump VERSION from 0.12.0 to 0.13.0
  - **Depends on**: T2, T3, T4
  - **Files**: `VERSION`
