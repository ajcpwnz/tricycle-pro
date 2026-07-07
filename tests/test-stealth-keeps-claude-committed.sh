#!/usr/bin/env bash
# TRI-21 amendment: stealth mode keeps .claude config COMMITTED.
#
# `tricycle generate gitignore` under stealth must:
#   1. write the .claude/* whitelist to the committed .gitignore, and
#   2. write a stealth block to .git/info/exclude that hides tricycle's own
#      internals (.trc/, specs/, configs, lock, .mcp.json) but NOT .claude/.
# Net effect: .claude/settings.json + commands/hooks/skills are committable,
# while .claude/settings.local.json and tricycle internals stay ignored.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$REPO_ROOT/bin/tricycle"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q

cat > tricycle.config.yml <<'YAML'
project:
  name: fixture
  type: single-app
  package_manager: npm
  base_branch: main
worktree:
  enabled: false
stealth:
  enabled: true
  ignore_target: exclude
YAML

"$CLI" generate gitignore >/dev/null

GI="$TMP/.gitignore"
EX="$TMP/.git/info/exclude"

# 1. Committed .gitignore carries the .claude whitelist
[ -f "$GI" ] || { echo "FAIL: .gitignore not written"; exit 1; }
grep -q '^\.claude/\*' "$GI"              || { echo "FAIL: .claude/* whitelist missing from .gitignore"; exit 1; }
grep -q '^!\.claude/settings\.json' "$GI" || { echo "FAIL: !.claude/settings.json missing from .gitignore"; exit 1; }

# 2. Stealth block hides tricycle internals but NOT .claude/
[ -f "$EX" ] || { echo "FAIL: .git/info/exclude not written"; exit 1; }
grep -q '# >>> tricycle stealth' "$EX"    || { echo "FAIL: stealth block missing from info/exclude"; exit 1; }
grep -q '^\.trc/' "$EX"                   || { echo "FAIL: .trc/ not stealthed"; exit 1; }
if grep -qE '^\.claude/?$' "$EX"; then echo "FAIL: .claude/ is still stealthed in info/exclude"; exit 1; fi

# 3. Effective ignore semantics via git check-ignore
mkdir -p "$TMP/.claude" "$TMP/.trc"
: > "$TMP/.claude/settings.json"
: > "$TMP/.claude/settings.local.json"
: > "$TMP/.trc/foo"

# .claude/settings.json must be COMMITTABLE (not ignored) -> check-ignore exits 1
if git -C "$TMP" check-ignore -q .claude/settings.json; then
  echo "FAIL: .claude/settings.json is ignored (should be committable)"; exit 1
fi
# .claude/settings.local.json must stay ignored
git -C "$TMP" check-ignore -q .claude/settings.local.json || { echo "FAIL: .claude/settings.local.json is not ignored (should be)"; exit 1; }
# tricycle internals must stay ignored
git -C "$TMP" check-ignore -q .trc/foo || { echo "FAIL: .trc/foo is not ignored (should be)"; exit 1; }

echo "PASS"
