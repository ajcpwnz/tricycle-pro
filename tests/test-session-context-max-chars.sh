#!/usr/bin/env bash
# The session-context injection cap is configurable, not a magic constant.
# `context.session_start.max_chars` in tricycle.config.yml must be emitted as a
# "# max_chars: N" directive in .session-context.conf (read by the hook);
# absent, no directive is written (hook falls back to its high default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$REPO_ROOT/bin/tricycle"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

CONF="$TMP/.claude/hooks/.session-context.conf"

# 1. With max_chars set → directive present
cat > tricycle.config.yml <<'YAML'
project:
  name: fixture
  type: single-app
  package_manager: npm
  base_branch: main
worktree:
  enabled: false
context:
  session_start:
    constitution: true
    max_chars: 42000
YAML
"$CLI" generate settings >/dev/null
[ -f "$CONF" ] || { echo "FAIL: conf not written"; exit 1; }
grep -q '^# max_chars: 42000$' "$CONF" || { echo "FAIL: max_chars directive missing"; cat "$CONF"; exit 1; }

# 2. Without max_chars → no directive
cat > tricycle.config.yml <<'YAML'
project:
  name: fixture
  type: single-app
  package_manager: npm
  base_branch: main
worktree:
  enabled: false
context:
  session_start:
    constitution: true
YAML
"$CLI" generate settings >/dev/null
if grep -q '^# max_chars:' "$CONF"; then echo "FAIL: directive written when unset"; cat "$CONF"; exit 1; fi

# 3. Hook default when no directive is 1,000,000 (not the old magic 50k/150k)
grep -q 'max_len=1000000' "$REPO_ROOT/core/hooks/session-context.sh" \
  || { echo "FAIL: hook default is not 1000000"; exit 1; }
if grep -qE 'max_len=(50000|150000)$' "$REPO_ROOT/core/hooks/session-context.sh"; then
  echo "FAIL: hardcoded magic cap still present"; exit 1
fi

echo "PASS"
