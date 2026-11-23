#!/usr/bin/env bash
# style-gate.sh lints persisted prose through the asd-ste100 linter, blocks on a
# hard finding, ignores advisory ones, lints only added text, and fails open when
# the plugin is absent or disabled. A stub linter stands in for the plugin.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/core/hooks/style-gate.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/claude"; PLUG="$CFG/plugins/cache/asd/asd-ste100/abc"
mkdir -p "$PLUG/scripts" "$TMP/repo"

# Stub linter: a semicolon is a hard finding, "is read" is advisory.
cat > "$PLUG/scripts/ste-lint.py" <<'PY'
import json, sys
t = sys.stdin.read()
v = []
if ";" in t: v.append({"rule": "semicolon", "level": "advisory-free", "match": ";", "message": "no semicolons"})
if "is read" in t: v.append({"rule": "passive-voice", "level": "advisory", "match": "is read", "message": "passive"})
if "check" in t.lower() and "verify" in t.lower() and "synonym-rotation" not in sys.argv:
    v.append({"rule": "synonym-rotation", "level": "advisory-free", "match": "verify", "message": "one word"})
print(json.dumps({"violations": v}))
PY
cat > "$CFG/plugins/installed_plugins.json" <<EOF
{"version": 2, "plugins": {"asd-ste100@asd-ste100-skill": [{"installPath": "$PLUG"}]}}
EOF
enable() { printf '{"enabledPlugins": {"asd-ste100@asd-ste100-skill": %s}}\n' "$1" > "$CFG/settings.json"; }
enable true

pass=0
check() { # <want> <label> <payload> [env assignment]
  local out got
  out=$(printf '%s' "$3" | env CLAUDE_CONFIG_DIR="$CFG" ${4:-} bash "$HOOK")
  got=ALLOW; printf '%s' "$out" | grep -q '"decision": "block"' && got=BLOCK
  [ "$got" = "$1" ] || { echo "FAIL: $2: want $1, got $got ($out)"; exit 1; }
  pass=$((pass + 1))
}
write() { jq -nc --arg f "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }
edit()  { jq -nc --arg f "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}'; }
bash_p() { jq -nc --arg c "$1" --arg d "$TMP/repo" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'; }

check BLOCK "markdown with a semicolon" "$(write "$TMP/repo/a.md" $'# A\n\nRun it; stop.\n')"
check ALLOW "clean markdown" "$(write "$TMP/repo/a.md" $'# A\n\nRun it. Stop.\n')"
check ALLOW "advisory finding only" "$(write "$TMP/repo/a.md" $'The file is read at start.\n')"
check ALLOW "code file" "$(write "$TMP/repo/a.ts" 'a; b;')"
check ALLOW "file under the Claude config dir" "$(write "$CFG/notes.md" 'a; b')"
printf '# Old\n\nOld line; kept.\n' > "$TMP/repo/old.md"
check ALLOW "Write keeps an old violation, adds clean text" "$(write "$TMP/repo/old.md" $'# Old\n\nOld line; kept.\n\nNew line.\n')"
check BLOCK "Write adds a violation" "$(write "$TMP/repo/old.md" $'# Old\n\nOld line; kept.\n\nNew; line.\n')"
check ALLOW "Edit adds clean text" "$(edit "$TMP/repo/old.md" 'Old line; kept.' $'Old line; kept.\nNew line.')"
check BLOCK "Edit adds a violation" "$(edit "$TMP/repo/old.md" 'Old line; kept.' 'New; line.')"
check ALLOW "git commit -m" "$(bash_p 'git commit -m "fix: run it; stop"')"
check ALLOW "clean git commit -m" "$(bash_p 'git commit -m "fix: run it"')"
check ALLOW "git commit heredoc" "$(bash_p $'git commit -m "$(cat <<\'EOF\'\nfix: run it; stop\nEOF\n)"')"
printf 'fix: a; b\n' > "$TMP/repo/msg.txt"
check ALLOW "git commit -F file" "$(bash_p 'git commit -F msg.txt')"
check BLOCK "gh pr create --body" "$(bash_p 'gh pr create --title t --body "Run it; stop"')"
check ALLOW "unrelated command with a semicolon" "$(bash_p 'ls; echo a; b')"
check ALLOW "script heredoc that only mentions a commit" "$(bash_p $'python3 - <<\'EOF\'\n# Checked: `git commit` messages; a; b\nEOF')"
check ALLOW "commit after another command" "$(bash_p 'git add -A && git commit -m "fix: a; b"')"
check ALLOW "heredoc file write, then a clean commit" "$(bash_p $'cat > a.ts <<\'EOF\'\nconst a = 1; const b = 2;\nEOF\ngit add -A && git commit -qm fixture')"
check ALLOW "commit -F - heredoc" "$(bash_p $'git commit -F - <<\'EOF\'\nfix: a; b\nEOF')"
check ALLOW "doc prose may rotate synonyms" "$(write "$TMP/repo/doc.md" 'Check the token. Then verify it.')"
check BLOCK "agent-facing text may not rotate synonyms" "$(write "$TMP/repo/.trc/blocks/plan/x.md" 'Check the token. Then verify it.')"
check BLOCK "CLAUDE.md is strict" "$(write "$TMP/repo/CLAUDE.md" 'Check the token. Then verify it.')"
check BLOCK "tracker issue description" '{"tool_name":"mcp__linear__save_issue","tool_input":{"title":"t","description":"Run it; stop"}}'
check BLOCK "tracker comment body" '{"tool_name":"mcp__linear__save_comment","tool_input":{"issueId":"X-1","body":"Run it; stop"}}'
check ALLOW "TRC_STYLE_GATE=0 turns it off" "$(write "$TMP/repo/a.md" 'Run it; stop.')" "TRC_STYLE_GATE=0"
enable false
check ALLOW "plugin disabled: fail open" "$(write "$TMP/repo/a.md" 'Run it; stop.')"
enable true
rm "$PLUG/scripts/ste-lint.py"
check ALLOW "linter missing: fail open" "$(write "$TMP/repo/a.md" 'Run it; stop.')"

echo "style-gate: OK ($pass cases)"
