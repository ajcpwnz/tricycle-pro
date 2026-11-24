#!/usr/bin/env bash
# init and update install a core hook script only when `generate settings`
# registers it: its config switch is on and claude.disable_core_hooks does not
# name it. update removes a managed copy that is no longer wanted. With
# style.artifacts: ste-short, session-context loads the skill at session start.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$(cd "$SCRIPT_DIR/.." && pwd)/bin/tricycle"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q
H="$TMP/.claude/hooks"
fail() { echo "FAIL: $1"; exit 1; }

write_cfg() { # <worktree.enabled> <extra yaml>
  printf 'project:\n  name: fixture\n  type: single-app\n  base_branch: main\nworktree:\n  enabled: %s\ncontext:\n  session_start:\n    constitution: false\n%s' "$1" "$2" > tricycle.config.yml
}

write_cfg true 'style:
  artifacts: ste-short
'
"$CLI" update >/dev/null 2>&1 || fail "first update exited non-zero"
for h in guard-main-checkout style-gate rename-on-kickoff graphify-refresh-on-kickoff session-context; do
  [ -f "$H/$h.sh" ] || fail "$h.sh not installed while wanted"
done
grep -q '"SessionStart"' .claude/settings.json || fail "style.artifacts: ste-short, but no SessionStart hook loads the skill"

write_cfg false 'claude:
  disable_core_hooks:
    - rename-on-kickoff
'
"$CLI" update >/dev/null 2>&1 || fail "second update exited non-zero"
for h in guard-main-checkout style-gate rename-on-kickoff session-context; do
  [ ! -e "$H/$h.sh" ] || fail "$h.sh kept after it became unwanted"
  ! grep -q "^\.claude/hooks/$h\.sh" .tricycle.lock || fail "$h.sh still in the lock"
done
[ -f "$H/graphify-refresh-on-kickoff.sh" ] || fail "graphify hook removed while wanted"

# A repo file with a core hook's name, not in the lock, is not touched.
printf '#!/bin/sh\n' > "$H/rename-on-kickoff.sh"
"$CLI" update >/dev/null 2>&1
[ -f "$H/rename-on-kickoff.sh" ] || fail "update deleted an unmanaged repo file"

"$CLI" generate settings >/dev/null
python3 - "$TMP/.claude/settings.json" <<'PY'
import json, sys
cmds = [h["command"] for es in json.load(open(sys.argv[1]))["hooks"].values() for e in es for h in e["hooks"]]
for name in ("guard-main-checkout", "style-gate", "rename-on-kickoff", "session-context"):
    assert not any(c.endswith("/" + name + ".sh") for c in cmds), (name, cmds)
assert any(c.endswith("/graphify-refresh-on-kickoff.sh") for c in cmds), cmds
PY
echo "update-core-hooks-wanted: OK"
