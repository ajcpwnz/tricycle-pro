# Contract: `tricycle dogfood` subcommand

**Status**: New subcommand in `bin/tricycle`. Contributor-facing only. Silent no-op in ordinary consumer repos.

## Invocation

```
tricycle dogfood [--yes | -y]
```

## Behavior

1. **Meta-repo detection.** If `$CWD/core/` is not a directory, print a one-line message and exit 0:
   ```
   Not a tricycle-pro meta-repo (no core/ directory at repo root); nothing to do.
   ```
   This is the ordinary-consumer safety valve (FR-002).

2. **Dry-run pass.** Walk every pair in `TRICYCLE_MANAGED_PATHS`. For each file under `core/<src>/**/*`, compute the destination path `<dst>/...`. Compare contents:
   - **dst missing**: print `ADD <dst-relpath>` (would create).
   - **dst differs**: print `WRITE <dst-relpath>` (would overwrite).
   - **dst matches**: nothing printed (already in sync).
   If nothing would change, print `Nothing to do — .trc/ and .claude/ already mirror core/.` and exit 0.

3. **Confirmation gate.** If `--yes` / `-y` was NOT passed, print:
   ```
   Dry run. Re-run with --yes to apply.
   ```
   Exit 0.

4. **Write pass** (only when `--yes`). For each file that would change:
   - `mkdir -p "$(dirname "<dst>")"`.
   - `cp -f "<src-file>" "<dst-file>"`.
   - If the file name ends in `.sh`: `chmod +x "<dst-file>"`.
   - Call `lock_set "<dst-relpath>" "<new-checksum>" "false"` so subsequent `tricycle update` runs don't SKIP it.
   After the loop: `save_lock` to persist the updated `.tricycle.lock`.

5. **Unmapped-core guard** (FR-008). While walking `core/`, if a file lives outside any mapping pair's source directory, collect it. At the end of the dry-run pass, print a separate warning block:
   ```
   Warning: unmapped paths under core/ (not mirrored):
     core/some/new/thing.md
     core/another/new/dir/
   Consider extending TRICYCLE_MANAGED_PATHS in bin/tricycle, or moving these files.
   ```
   Do NOT silently drop or invent a destination for unmapped files.

6. **Summary.** Final line:
   - Dry-run: `Would: N adopted, M added.`
   - Write: `N adopted, M added.`
   Where "adopted" = overwritten-with-core-content, "added" = created-new-from-core.

## Exit codes

- `0` — success (including the no-op / dry-run / not-a-meta-repo paths).
- `1` — unrecoverable error (write failed, unreadable `core/`, lock save failed).

No reserved-range codes (unlike TRI-26 / TRI-32). Failures are flat.

## Side effects

- Writes: filesystem overwrites under `.trc/` and `.claude/` (only with `--yes`).
- Writes: `.tricycle.lock` update (only with `--yes`).
- Reads: every file under `core/<src>` in `TRICYCLE_MANAGED_PATHS`, plus whatever lives in `core/` for the unmapped-guard pass.
- Never touches: `.claude/skills/` (FR-007), files outside the mapping table (FR-008), `tricycle.config.yml`, git state.

## Help text

```
tricycle dogfood [--yes | -y]   Mirror this repo's own core/ into .trc/ and .claude/
                                (contributor-only; no-op in consumer repos)
```

Full `--help` lists `--yes` as: "write changes. Without this flag, runs as a dry-run."

---

# Contract: `TRICYCLE_MANAGED_PATHS` shared mapping

**Status**: New shared array declared near the top of `bin/tricycle`, consumed by both `cmd_update` (refactored) and `cmd_dogfood` (new). Single source of truth for `core/ → consumer-path` mapping (FR-003).

## Shape

```bash
# Format: "src-under-repo-root:dst-under-repo-root"
TRICYCLE_MANAGED_PATHS=(
  "core/commands:.claude/commands"
  "core/templates:.trc/templates"
  "core/scripts/bash:.trc/scripts/bash"
  "core/hooks:.claude/hooks"
  "core/blocks:.trc/blocks"
)
```

`cmd_update`'s inline for-loop literal is replaced by a loop over `"${TRICYCLE_MANAGED_PATHS[@]}"`. Behavior of `cmd_update` is unchanged.

---

# Contract: `tests/test-dogfood-drift.sh`

**Status**: New test script wired into `tests/run-tests.sh`. Skips when `core/` is absent (consumer fixtures).

## Behavior

1. If `core/` does not exist at repo root → print one line (`dogfood-drift: skipped (not a meta-repo)`) and exit 0.
2. Otherwise, for each pair in `TRICYCLE_MANAGED_PATHS`:
   - Run `diff -r <src> <dst>`.
   - If `diff` reports any difference, capture it and fail.
3. On failure: print each drifted path (one per line) followed by the actual diff, exit 1.
4. On no drift: print `dogfood-drift: OK` and exit 0.

## Integration with `tests/run-tests.sh`

One new `run_test` entry in the existing suite. Test is silently-green in consumer fixtures; fails loudly if `.trc/` drifts from `core/` in tricycle-pro itself.

---

# Contract: `--help` surface change

`bin/tricycle`'s `show_help` gains one new line:

```
  tricycle dogfood [--yes]      Mirror this repo's core/ into .trc/ and .claude/ (contributor-only)
```

No other `--help` changes.
