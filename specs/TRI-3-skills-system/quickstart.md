# Quickstart: TRI-3 Skills System

**Date**: 2026-03-27

## For Developers Working on This Feature

### Key Files to Modify

1. **`bin/tricycle`** — Main CLI: add `cmd_skills()`, modify `cmd_init()` and `cmd_update()`
2. **`bin/lib/helpers.sh`** — Add `install_skills()`, `fetch_external_skill()`, `generate_source_file()`, `skill_checksum()`
3. **`core/skills/`** — Add vendored skill directories (code-reviewer, tdd, debugging, document-writer)
4. **`tests/run-tests.sh`** — Add skill install/disable/list test groups

### Existing Patterns to Follow

- **File installation**: Use `install_file()` and `install_dir()` from `helpers.sh` — they handle checksums and lock tracking
- **Config access**: Use `cfg_get()`, `cfg_count()`, `cfg_has()` — config is already parsed to KEY=VALUE
- **Subcommands**: Follow `cmd_add()` / `cmd_generate()` dispatch pattern in `bin/tricycle`
- **Testing**: Follow existing test groups in `tests/run-tests.sh` using `assert_*` helpers

### Running Tests

```bash
# Full test suite
bash tests/run-tests.sh

# Block/config tests
node --test tests/test-*.js
```

### Quick Verification

```bash
# After implementing, verify with:
cd /tmp && mkdir test-project && cd test-project
tricycle init --preset single-app

# Check skills installed
ls .claude/skills/
# Expected: code-reviewer/ debugging/ document-writer/ monorepo-structure/ tdd/

# Check SOURCE files
cat .claude/skills/code-reviewer/SOURCE

# Test disable
# Add skills.disable: [tdd] to tricycle.config.yml
tricycle update
# tdd should be skipped

# Test list
tricycle skills list
```
