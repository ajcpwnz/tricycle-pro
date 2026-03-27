# Tasks: Fix Template Engine Awk Syntax Error

## Phase 1: Fix

- [x] T001 Fix `process_if_blocks()` awk variable naming and regex issues in bin/lib/template_engine.sh — rename `-v close=` to `-v ctag=`, replace `sub()` calls with `index()`+`substr()` for literal string matching
- [x] T002 Add `generate claude-md` test for all presets to tests/run-tests.sh — verify no stderr errors and output contains project name
- [x] T003 Bump version from 0.8.0 to 0.8.1 in VERSION
- [x] T004 Run full test suite and fix any failures
