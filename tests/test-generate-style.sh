#!/usr/bin/env bash
# `tricycle generate settings` turns the style config into its outputs:
# style.artifacts: ste-short registers the style-gate hook, style.chat writes
# .caveman.json, no style block writes and registers nothing, and an unknown
# chat mode fails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$(cd "$SCRIPT_DIR/.." && pwd)/bin/tricycle"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$TMP/on" "$TMP/off" "$TMP/bad"
printf 'project:\n  name: on\nstyle:\n  chat: ultracave\n  artifacts: ste-short\n' > "$TMP/on/tricycle.config.yml"
printf 'project:\n  name: off\n' > "$TMP/off/tricycle.config.yml"
printf 'project:\n  name: bad\nstyle:\n  chat: loud\n' > "$TMP/bad/tricycle.config.yml"

(cd "$TMP/on" && "$CLI" generate settings >/dev/null)
python3 - "$TMP/on" <<'PY'
import json, sys
d = sys.argv[1]
hooks = json.load(open(d + "/.claude/settings.json"))["hooks"]["PreToolUse"]
gate = [e for e in hooks for h in e["hooks"] if h["command"].endswith("/style-gate.sh")]
assert len(gate) == 1, "style-gate not registered once"
assert "Write" in gate[0]["matcher"] and "Bash" in gate[0]["matcher"] and "save" in gate[0]["matcher"], gate[0]["matcher"]
assert json.load(open(d + "/.caveman.json")) == {"defaultMode": "ultracave"}
conf = open(d + "/.claude/hooks/.session-context.conf").read().splitlines()
assert ".claude/skills/ste-short/SKILL.md" in conf, "ste-short skill not injected at session start"
PY

(cd "$TMP/off" && "$CLI" generate settings >/dev/null)
[ ! -e "$TMP/off/.caveman.json" ] || fail "no style.chat, but .caveman.json written"
! grep -q style-gate "$TMP/off/.claude/settings.json" || fail "no style.artifacts, but style-gate registered"
! grep -qs ste-short "$TMP/off/.claude/hooks/.session-context.conf" || fail "no style.artifacts, but ste-short injected"

if (cd "$TMP/bad" && "$CLI" generate settings >/dev/null 2>&1); then fail "unknown style.chat mode accepted"; fi

echo "generate-style: OK"
