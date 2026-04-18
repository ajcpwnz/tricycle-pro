#!/usr/bin/env bash
# Asserts `tricycle generate settings` registers the graphify-refresh hook
# alongside the rename-on-kickoff hook, and that the source file ships.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$REPO_ROOT/bin/tricycle"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
cat > tricycle.config.yml <<'YAML'
project:
  name: fixture
  type: single-app
  package_manager: npm
  base_branch: main
worktree:
  enabled: false
YAML

"$CLI" generate settings >/dev/null

SETTINGS="$TMP/.claude/settings.json"
[ -f "$SETTINGS" ] || { echo "FAIL: settings.json not written"; exit 1; }

python3 - "$SETTINGS" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hooks = data.get("hooks", {})
ups = hooks.get("UserPromptSubmit")
assert isinstance(ups, list) and ups, "UserPromptSubmit array missing or empty"
first = ups[0]
inner = first.get("hooks") or []
cmds = [h.get("command", "") for h in inner]
assert ".claude/hooks/rename-on-kickoff.sh" in cmds, f"rename hook missing; got {cmds}"
assert ".claude/hooks/graphify-refresh-on-kickoff.sh" in cmds, f"graphify hook missing; got {cmds}"
# Rename must come first so the session label is set before graphify fires.
assert cmds.index(".claude/hooks/rename-on-kickoff.sh") < cmds.index(".claude/hooks/graphify-refresh-on-kickoff.sh"), \
    f"rename hook must come before graphify; got {cmds}"
PY

# Source file must exist and be executable.
[ -x "$REPO_ROOT/core/hooks/graphify-refresh-on-kickoff.sh" ] \
  || { echo "FAIL: core/hooks/graphify-refresh-on-kickoff.sh missing or not executable"; exit 1; }

echo "generate-settings-graphify-hook: OK"
