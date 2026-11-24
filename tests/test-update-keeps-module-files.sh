#!/usr/bin/env bash
# tricycle update keeps the files that a module installed, regenerates
# settings.json so that it registers no removed hook, deletes the directories
# that a removal left empty, and writes nothing on a second run.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$ROOT/bin/tricycle"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q
fail() { echo "FAIL: $1"; exit 1; }
printf 'project:\n  name: fixture\n  type: single-app\n  base_branch: main\nworktree:\n  enabled: true\n' > tricycle.config.yml

"$CLI" update >/dev/null 2>&1 || fail "first update exited non-zero"
"$CLI" generate settings >/dev/null 2>&1 || fail "generate settings exited non-zero"
"$CLI" add ci-watch >/dev/null 2>&1 || fail "add ci-watch exited non-zero"
[ -f .claude/commands/wait-ci.md ] || fail "add ci-watch did not install wait-ci.md"

# A hook and a block that core no longer ships, as an old version left them.
mkdir -p .trc/blocks/retired-step
echo old > .trc/blocks/retired-step/old.md
echo '#!/bin/sh' > .claude/hooks/retired-hook.sh
python3 - <<'PY'
import json
lock = json.load(open(".tricycle.lock"))
for p in (".trc/blocks/retired-step/old.md", ".claude/hooks/retired-hook.sh"):
    lock["files"][p] = {"checksum": "0"}
json.dump(lock, open(".tricycle.lock", "w"), indent=2)
s = json.load(open(".claude/settings.json"))
s.setdefault("hooks", {}).setdefault("PreToolUse", []).append(
    {"matcher": "Bash", "hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/retired-hook.sh"}]})
json.dump(s, open(".claude/settings.json", "w"), indent=2)
PY

"$CLI" update >/dev/null 2>&1 || fail "second update exited non-zero"
[ -f .claude/commands/wait-ci.md ] || fail "update removed the module file wait-ci.md"
grep -q '"\.claude/commands/wait-ci\.md"' .tricycle.lock || fail "wait-ci.md left the lock"
[ ! -e .claude/hooks/retired-hook.sh ] || fail "the retired hook was not removed"
! grep -q retired-hook .claude/settings.json || fail "settings.json still registers the removed hook"
[ ! -e .trc/blocks/retired-step ] || fail "the emptied directory .trc/blocks/retired-step is still there"

git add -A && git -c user.name=t -c user.email=t@example.test commit -qm one
OUT=$("$CLI" update 2>&1)
[ -z "$(git status --porcelain)" ] || { git status --short; fail "third update changed files"; }
! printf '%s\n' "$OUT" | grep -q "WRITE" || fail "third update wrote files: $(printf '%s\n' "$OUT" | grep WRITE)"
echo "update-keeps-module-files: OK"
