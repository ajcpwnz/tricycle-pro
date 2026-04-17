# Contract: `tests/test-dogfood-drift.sh` (one-way revision)

**Status**: In-place revision of the v0.20.1 test. Public contract (exit code + stderr/stdout shape) stays compatible — only the internal drift definition narrows.

## Behavior

1. If `$REPO_ROOT/core/` does not exist → print `dogfood-drift: skipped (not a meta-repo)` and exit 0.
2. For each `<src-dir>:<dst-dir>` pair in the hardcoded mapping table:
   - If `<src-dir>` does not exist as a directory under `$REPO_ROOT` → skip the pair (same as v0.20.1).
   - If `<dst-dir>` does not exist as a directory under `$REPO_ROOT` → flag the pair as drifted with `(missing directory)` suffix on the path line.
   - Otherwise: `find "$REPO_ROOT/<src-dir>" -type f | sort` and for each file:
     - Compute `rel="${src_path#$REPO_ROOT/<src-dir>/}"` and `dst_path="$REPO_ROOT/<dst-dir>/$rel"`.
     - If `! -f "$dst_path"` → state: **missing**. Record `<dst-dir>/$rel` with `(missing)` suffix.
     - Else if `cmp -s "$src_path" "$dst_path"` returns non-zero → state: **differ**. Record `<dst-dir>/$rel` plus a `diff "$src_path" "$dst_path"` block in the details buffer.
     - Else: state **match**, record nothing.
3. If no paths were recorded → print `dogfood-drift: OK` and exit 0.
4. Otherwise → print `FAIL: dogfood drift detected between core/ and mirrored paths.`, then `Drifted paths:` and the list (one per line), then `Detail:` and the accumulated diff blocks, then a final `Fix: run 'tricycle dogfood --yes' from the repo root to re-mirror core/, or intentional divergence must be lifted into core/.` line. Exit 1.

## Exit codes

- `0` — no drift (including the consumer-fixture skip).
- `1` — drift detected.

Same codes as v0.20.1. Callers can continue to treat `0` as green, `1` as red without change.

## What this test explicitly does NOT flag

- Files present under `<dst-dir>` with no `<src-dir>/<rel>` counterpart (runtime-generated files like `.claude/hooks/.session-context.conf`, orphans, etc.).
- Files outside the five mapping pairs entirely.
- Any symlinks or special files inside `<src-dir>` (because `find -type f` filters them — consistent with v0.20.1).

## Invariants

- One-way walk — `find` iterates `<src-dir>` only.
- No `diff -r`. No bidirectional comparison. Any future edit that reintroduces `-r` reintroduces the false-positive class TRI-34 closes.
- Hardcoded mapping list kept in lockstep with `bin/tricycle`'s `TRICYCLE_MANAGED_PATHS` by convention (R3). Future refactor may source a shared file.
