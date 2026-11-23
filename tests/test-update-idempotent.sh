#!/usr/bin/env bash
# tricycle update copies core files byte for byte, keeps every lock entry
# (also a path with "version" in it), writes nothing on a second run, and
# removes a disabled skill that it installed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$ROOT/bin/tricycle"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q
fail() { echo "FAIL: $1"; exit 1; }
printf 'project:\n  name: fixture\n  type: single-app\n  base_branch: main\nworktree:\n  enabled: true\n' > tricycle.config.yml

"$CLI" update >/dev/null 2>&1 || fail "first update exited non-zero"
for f in "$ROOT"/core/scripts/bash/*.sh; do
  cmp -s "$f" ".trc/scripts/bash/$(basename "$f")" || fail "$(basename "$f") is not a byte-exact copy"
done
grep -q '"\.trc/blocks/implement/version-bump\.md"' .tricycle.lock || fail "version-bump.md missing from the lock"

git add -A && git -c user.name=t -c user.email=t@example.test commit -qm one
OUT=$("$CLI" update 2>&1)
[ -z "$(git status --porcelain)" ] || { git status --short; fail "second update changed files"; }
printf '%s\n' "$OUT" | grep -q "0 updated, 0 added, 0 adopted, 0 removed" || fail "second update reported work: $(printf '%s' "$OUT" | tail -1)"
! printf '%s\n' "$OUT" | grep -q "WRITE" || fail "second update wrote files"

printf 'skills:\n  disable: [tdd]\n' >> tricycle.config.yml
"$CLI" update >/dev/null 2>&1
[ ! -e .claude/skills/tdd ] || fail "disabled managed skill not removed"
! grep -q '"\.claude/skills/tdd/' .tricycle.lock || fail "disabled skill still in the lock"
echo "update-idempotent: OK"
