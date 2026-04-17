# Quickstart: One-way drift check

**Feature**: TRI-34
**Audience**: Contributors verifying the feature after `/trc.implement`.

## Setup

Work in the tricycle-pro meta-repo with `core/` + synced `.trc/` + `.claude/*`. If the state is drifted, start with `tricycle dogfood --yes`.

## Test 1 — False positive is gone (User Story 1)

```bash
# Ensure the runtime-generated file exists:
tricycle generate settings >/dev/null
ls .claude/hooks/.session-context.conf   # confirm it exists

bash tests/test-dogfood-drift.sh
```

**Expected**: Exit 0. Output is a single line: `dogfood-drift: OK`. The `.session-context.conf` extra in `.claude/hooks/` does NOT trigger drift.

## Test 2 — Modified core/ file is still caught (User Story 2)

```bash
printf '\n# TRI-34 test marker\n' >> core/scripts/bash/derive-branch-name.sh

bash tests/test-dogfood-drift.sh
# Exit 1. Output names `.trc/scripts/bash/derive-branch-name.sh` and shows the diff.

git checkout -- core/scripts/bash/derive-branch-name.sh
bash tests/test-dogfood-drift.sh
# Exit 0. `dogfood-drift: OK`.
```

## Test 3 — Missing destination file is caught (FR-005)

```bash
mv .trc/scripts/bash/derive-branch-name.sh /tmp/save.sh
bash tests/test-dogfood-drift.sh
# Exit 1. Output flags `.trc/scripts/bash/derive-branch-name.sh (missing)`.

mv /tmp/save.sh .trc/scripts/bash/derive-branch-name.sh
bash tests/test-dogfood-drift.sh
# Exit 0.
```

## Test 4 — Consumer fixture skip (FR-004)

```bash
cd /tmp && mkdir -p consumer-fixture && cd consumer-fixture
cp -r /Users/alex/projects/tricycle-pro/tests /tmp/consumer-fixture/tests
bash tests/test-dogfood-drift.sh
# Exit 0. Output: `dogfood-drift: skipped (not a meta-repo)`.
```

## Test 5 — Multiple drifts all reported (SC-003)

```bash
printf '\n# drift 1\n' >> core/scripts/bash/derive-branch-name.sh
printf '\n# drift 2\n' >> core/scripts/bash/create-new-feature.sh
bash tests/test-dogfood-drift.sh
# Exit 1. Both paths appear under `Drifted paths:`, both diffs appear under `Detail:`.
git checkout -- core/
```

## Test 6 — Full suite green post-landing

```bash
bash tests/run-tests.sh
# Exit 0. `Dogfood drift sync (TRI-33):` block shows both tests green.
```
