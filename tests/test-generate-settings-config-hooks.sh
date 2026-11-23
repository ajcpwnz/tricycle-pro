#!/usr/bin/env bash
# `tricycle generate settings` builds .claude/settings.json only from config:
# repo hooks from claude.hooks, repo permissions from claude.permissions.allow,
# and claude.disable_core_hooks drops named trc core hooks. A hand edit to the
# output is discarded, and two runs produce the same bytes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$(cd "$SCRIPT_DIR/.." && pwd)/bin/tricycle"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

cat > tricycle.config.yml <<'YAML'
project:
  name: fixture
  type: single-app
  package_manager: npm
worktree:
  enabled: true
claude:
  disable_core_hooks:
    - rename-on-kickoff
  permissions:
    allow:
      - "Bash(make:*)"
  hooks:
    - event: PreToolUse
      matcher: Bash
      command: $CLAUDE_PROJECT_DIR/.claude/hooks/a.sh
    - event: PreToolUse
      matcher: Bash
      command: $CLAUDE_PROJECT_DIR/.claude/hooks/b.sh
    - event: PreToolUse
      matcher: "mcp__.*__(save_issue|issue_write)"
      command: $CLAUDE_PROJECT_DIR/.claude/hooks/c.sh
    - event: Stop
      command: $CLAUDE_PROJECT_DIR/.claude/hooks/d.sh
      timeout: 10
YAML

"$CLI" generate settings >/dev/null
SETTINGS="$TMP/.claude/settings.json"
cp "$SETTINGS" "$TMP/first.json"

python3 - "$SETTINGS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
H = "$CLAUDE_PROJECT_DIR/.claude/hooks/"
hooks = d["hooks"]
def cmds(event):
    return [(e.get("matcher"), h["command"], h.get("timeout")) for e in hooks.get(event, []) for h in e["hooks"]]
pre = cmds("PreToolUse")
assert (None, None, None) not in pre
assert ("Bash", H + "guard-main-checkout.sh", 5) in pre, pre
assert ("Bash", H + "a.sh", None) in pre and ("Bash", H + "b.sh", None) in pre, pre
assert ("mcp__.*__(save_issue|issue_write)", H + "c.sh", None) in pre, pre
bash_entries = [e for e in hooks["PreToolUse"] if e.get("matcher") == "Bash"]
assert len(bash_entries) == 1 and len(bash_entries[0]["hooks"]) == 3, "same-matcher hooks must share one entry"
assert cmds("Stop") == [(None, H + "d.sh", 10)], cmds("Stop")
ups = [c for _, c, _ in cmds("UserPromptSubmit")]
assert H + "rename-on-kickoff.sh" not in ups, "disabled core hook still registered"
assert H + "graphify-refresh-on-kickoff.sh" in ups, ups
assert "PostToolUse" not in hooks, "no core hook registers PostToolUse"
assert "Bash(make:*)" in d["permissions"]["allow"], d["permissions"]["allow"]
PY

printf '{"hand": "edit"}\n' > "$SETTINGS"
"$CLI" generate settings >/dev/null
cmp -s "$TMP/first.json" "$SETTINGS" || { echo "FAIL: a hand edit survived regeneration, or output is not deterministic"; exit 1; }
echo "PASS"
