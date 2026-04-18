#!/usr/bin/env bash
# Asserts `tricycle generate settings` registers the TRI-31
# UserPromptSubmit hook and that `tricycle init` ships the hook file.
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
assert ".claude/hooks/rename-on-kickoff.sh" in cmds, f"rename-on-kickoff.sh not registered; got {cmds}"
PY

# Ensure the hook file itself ships via `install_dir`. We simulate this by
# checking the source is where install_dir expects it.
[ -x "$REPO_ROOT/core/hooks/rename-on-kickoff.sh" ] \
  || { echo "FAIL: core/hooks/rename-on-kickoff.sh missing or not executable"; exit 1; }

# `generate settings` registers the hook path; the script file MUST land on
# disk in the same run — otherwise Claude Code fails every kickoff prompt
# with "No such file or directory". Regression guard for that bug.
HOOK="$TMP/.claude/hooks/rename-on-kickoff.sh"
[ -x "$HOOK" ] \
  || { echo "FAIL: .claude/hooks/rename-on-kickoff.sh not installed by generate settings"; exit 1; }

echo "generate-settings-rename-hook: OK"
