#!/usr/bin/env bash
# Black-box tests for `tricycle graphify <sub>`. Uses PATH-injected stubs
# so no real `pip install` or graphify runtime is required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$REPO_ROOT/bin/tricycle"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

# ── status when nothing is installed ────────────────────────────────────────
# Mask any real graphify on PATH and any importable `graphify` module.
ISOLATE_PATH="/usr/bin:/bin"
if ! PATH="$ISOLATE_PATH" command -v graphify >/dev/null 2>&1 \
   && ! PATH="$ISOLATE_PATH" python3 -c 'import graphify' >/dev/null 2>&1; then
  out=$(PATH="$ISOLATE_PATH" "$CLI" graphify status 2>&1)
  echo "$out" | grep -q "installed:  false" \
    || { echo "FAIL: uninstalled status should show installed:false; got:"; echo "$out"; exit 1; }
  echo "$out" | grep -q "graph:      false" \
    || { echo "FAIL: uninstalled status should show graph:false"; exit 1; }
  echo "$out" | grep -q "mcp:        false" \
    || { echo "FAIL: mcp should report 'false'"; exit 1; }
else
  echo "  (skipping uninstalled-status subtest: graphify present on host)"
fi

# ── status --json ───────────────────────────────────────────────────────────
out=$("$CLI" graphify status --json 2>&1)
python3 - "$out" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert isinstance(d.get("installed"), bool), "installed must be bool"
assert isinstance(d.get("graph"), bool), "graph must be bool"
assert "graph_file" in d, "graph_file missing"
PY

# ── mcp-start / mcp-stop: registration lifecycle ────────────────────────────
# MCP stdio servers are spawned by the CLIENT (Claude Code), not as a daemon.
# mcp-start adds a "graphify" entry to .mcp.json; mcp-stop removes it.
# TRC_GRAPHIFY_MCP_CMD lets us substitute the spawn command so we don't need
# the real `graphify.serve` module or the [mcp] extra in CI.
STUB_DIR="$TMP/stub-bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/graphify" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  update*) echo "stub update" ; exit 0 ;;
  *) echo "stub $*" ; exit 0 ;;
esac
EOF
chmod +x "$STUB_DIR/graphify"

rm -f "$TMP/.mcp.json"
PATH="$STUB_DIR:$PATH" TRC_GRAPHIFY_MCP_CMD="sleep 30" \
  "$CLI" graphify mcp-start --run-id test-run >/dev/null

[ -f "$TMP/.mcp.json" ] || { echo "FAIL: .mcp.json not created"; exit 1; }
python3 - "$TMP/.mcp.json" <<'PY' || { echo "FAIL: graphify not in .mcp.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert "mcpServers" in d, "mcpServers section missing"
assert "graphify" in d["mcpServers"], f"graphify server missing; got {list(d['mcpServers'])}"
srv = d["mcpServers"]["graphify"]
assert srv["command"] == "sleep", f"unexpected command: {srv}"
PY

# mcp-start is idempotent — second call keeps a single graphify entry.
PATH="$STUB_DIR:$PATH" TRC_GRAPHIFY_MCP_CMD="sleep 30" \
  "$CLI" graphify mcp-start --run-id test-run >/dev/null
python3 - "$TMP/.mcp.json" <<'PY' || { echo "FAIL: idempotency check"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert list(d["mcpServers"]).count("graphify") == 1
PY

# mcp-stop removes the entry.
PATH="$STUB_DIR:$PATH" "$CLI" graphify mcp-stop --run-id test-run >/dev/null
python3 - "$TMP/.mcp.json" <<'PY' || { echo "FAIL: graphify still in .mcp.json"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert "graphify" not in (d.get("mcpServers") or {}), f"still present: {d}"
PY

# mcp-stop is safe to call when nothing is registered.
PATH="$STUB_DIR:$PATH" "$CLI" graphify mcp-stop --run-id test-run >/dev/null
PATH="$STUB_DIR:$PATH" "$CLI" graphify mcp-stop >/dev/null

# status reflects registration (false here since we just stopped).
out=$(PATH="$STUB_DIR:$PATH" "$CLI" graphify status 2>&1)
echo "$out" | grep -q "mcp:        false" \
  || { echo "FAIL: status should report mcp:false after stop; got:"; echo "$out"; exit 1; }

# ── refresh is silent when config missing flags ────────────────────────────
# With no graphify, no graph, and no auto-*, refresh should return 0
# without touching graphify-out.
rm -rf "$TMP/graphify-out"
PATH="$ISOLATE_PATH" "$CLI" graphify refresh
[ -d "$TMP/graphify-out" ] && {
  # Allowed: only if auto-paths populated it; we passed no env.
  # In our invocation we didn't set TRC_GRAPHIFY_AUTO_*; confirm empty.
  if [ -n "$(ls -A "$TMP/graphify-out" 2>/dev/null)" ]; then
    echo "FAIL: refresh with no-auto flags touched graphify-out/"
    ls -la "$TMP/graphify-out"
    exit 1
  fi
}

# ── Usage with no subcommand ────────────────────────────────────────────────
out=$("$CLI" graphify 2>&1) && {
  echo "FAIL: bare \`tricycle graphify\` should exit non-zero"
  exit 1
} || true

# ── Unknown subcommand ──────────────────────────────────────────────────────
if "$CLI" graphify bogus-sub >/dev/null 2>&1; then
  echo "FAIL: unknown subcommand should exit non-zero"
  exit 1
fi

echo "tricycle-graphify-cmd: OK"
