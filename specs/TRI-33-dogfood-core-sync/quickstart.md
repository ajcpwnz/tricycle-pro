# Quickstart: Dogfood drift sync

**Feature**: TRI-33
**Audience**: Contributors verifying the feature after `/trc.implement`.

## Test 1 — Dry-run reports drift (User Story 1)

```bash
cd /path/to/tricycle-pro
# Create an artificial drift:
printf '\n# marker\n' >> core/scripts/bash/derive-branch-name.sh
tricycle dogfood
```

**Expected**: Exit 0. Stdout lists `WRITE .trc/scripts/bash/derive-branch-name.sh` and ends with `Dry run. Re-run with --yes to apply.`. No filesystem writes.

## Test 2 — `--yes` applies (User Story 1)

```bash
tricycle dogfood --yes
diff core/scripts/bash/derive-branch-name.sh .trc/scripts/bash/derive-branch-name.sh
```

**Expected**: `diff` is empty. `.tricycle.lock` records the new checksum with `customized: false`.

## Test 3 — Post-sync `tricycle update --dry-run` shows no SKIPs on mirrored paths (SC-003)

```bash
tricycle update --dry-run
```

**Expected**: No `SKIP .trc/scripts/bash/derive-branch-name.sh` line. Other intentionally-customized files may still SKIP, but the mirrored ones should be clean.

## Test 4 — Consumer fixture: no-op (User Story 2)

```bash
cd /tmp/consumer-fixture   # a repo with tricycle.config.yml but NO core/
tricycle dogfood
```

**Expected**: Exit 0. One line: `Not a tricycle-pro meta-repo (no core/ directory at repo root); nothing to do.`. No filesystem changes.

## Test 5 — Drift test catches regressions (User Story 3)

```bash
cd /path/to/tricycle-pro
# Intentionally break the mirror:
printf '# drift\n' >> .trc/scripts/bash/derive-branch-name.sh
bash tests/run-tests.sh
```

**Expected**: Test suite fails with `dogfood-drift` reporting `.trc/scripts/bash/derive-branch-name.sh` as drifted. Output includes the actual diff.

```bash
# Restore:
git checkout -- .trc/scripts/bash/derive-branch-name.sh
bash tests/run-tests.sh
```

**Expected**: Green. `dogfood-drift: OK`.

## Test 6 — Unmapped-core file surfaces as warning (FR-008)

```bash
cd /path/to/tricycle-pro
mkdir -p core/uncharted
printf 'new\n' > core/uncharted/newthing.md
tricycle dogfood
```

**Expected**: Exit 0 (dry-run). Output includes a `Warning: unmapped paths under core/` block listing `core/uncharted/newthing.md`. The file is NOT mirrored anywhere.

```bash
rm -rf core/uncharted   # clean up
```

## Test 7 — Existing consumer `tricycle update` behavior is unchanged (SC-004)

```bash
cd /tmp/consumer-fixture
tricycle update   # before TRI-33 landed this produced output X
# After TRI-33 landed, same invocation should produce byte-identical output X
```

**Expected**: Output diff against a pre-TRI-33 capture is empty. (Captured by the existing `tests/test-tricycle-update-adopt.sh` + the new drift test's no-op path.)

## Test 8 — Executable bits preserved (FR-005)

```bash
chmod -x .trc/scripts/bash/derive-branch-name.sh
tricycle dogfood --yes
ls -l .trc/scripts/bash/derive-branch-name.sh
```

**Expected**: `+x` restored.
