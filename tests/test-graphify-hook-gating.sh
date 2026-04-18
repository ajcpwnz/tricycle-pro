#!/usr/bin/env bash
# Exercises every silent-skip gate in graphify-refresh-on-kickoff.sh so
# downstream repos upgrade with zero impact regardless of install state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/core/hooks/graphify-refresh-on-kickoff.sh"

[ -x "$HOOK" ] || { echo "FAIL: hook not executable at $HOOK"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q

# Minimal config with graphify block OFF — default posture.
write_config_off() {
  cat > "$TMP/tricycle.config.yml" <<'YAML'
project:
  name: fixture
integrations:
  graphify:
    enabled: false
    refresh_on_kickoff: true
YAML
}

write_config_on() {
  cat > "$TMP/tricycle.config.yml" <<'YAML'
project:
  name: fixture
integrations:
  graphify:
    enabled: true
    refresh_on_kickoff: true
    auto_install: false
    auto_bootstrap: false
YAML
}

# Capture any residue the hook would leave behind so we can confirm
# "silent skip" really means skip — no log file, no pid file, no process.
assert_no_residue() {
  local label="$1"
  if [ -d "$TMP/graphify-out" ]; then
    echo "FAIL ($label): graphify-out/ was created on a silent-skip path"
    ls -la "$TMP/graphify-out"
    exit 1
  fi
}

run_hook() {
  local prompt="$1"
  printf '{"prompt":%s}\n' "$(printf '%s' "$prompt" | jq -Rs .)" \
    | "$HOOK"
}

# ── Gate 1: non-kickoff prompt ──────────────────────────────────────────────
write_config_on
run_hook "hello, not a slash command"
assert_no_residue "non-kickoff prompt"
# Now a kickoff command but buried inside free text — should still skip.
run_hook "please run /trc.specify later for me"
# Note: `/trc.specify later ...` is detected as a kickoff. The string above
# has it mid-sentence so it's NOT a kickoff. But the hook only checks the
# trimmed prefix, so free-text prefix means no match → exit 0.
assert_no_residue "free-text-wrapped kickoff"

# ── Gate 2: config flag OFF ─────────────────────────────────────────────────
write_config_off
rm -rf "$TMP/graphify-out"
run_hook "/trc.specify do a thing"
assert_no_residue "flag off"

# ── Gate 2b: refresh_on_kickoff explicitly false ────────────────────────────
cat > "$TMP/tricycle.config.yml" <<'YAML'
project:
  name: fixture
integrations:
  graphify:
    enabled: true
    refresh_on_kickoff: false
YAML
rm -rf "$TMP/graphify-out"
run_hook "/trc.chain FOO-1,FOO-2"
assert_no_residue "refresh_on_kickoff false"

# ── Gate 3: graphify not installed AND auto_install false ──────────────────
# Shield the test from any graphify actually installed on the host by
# giving PATH no python and no graphify. We can't fully mask the system
# python — if it happens to have `import graphify` succeed, we skip this
# gate. This is a defensive check, not a full sandbox.
write_config_on
rm -rf "$TMP/graphify-out"
if ! command -v graphify >/dev/null 2>&1 && ! python3 -c 'import graphify' >/dev/null 2>&1; then
  run_hook "/trc.specify X"
  assert_no_residue "graphify missing, auto_install off"
else
  echo "  (skipping gate-3 subtest: graphify present on host)"
fi

# ── Gate 4: graphify faked-present but no graph file, auto_bootstrap off ────
# Simulate "graphify is installed" via PATH-injected stub.
STUB_DIR="$TMP/stub-bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/graphify" <<'EOF'
#!/usr/bin/env bash
# Deliberate no-op; records an invocation so we can assert later.
echo "STUB $*" >> "$TMP_STUB_LOG"
EOF
chmod +x "$STUB_DIR/graphify"

write_config_on
rm -rf "$TMP/graphify-out"
TMP_STUB_LOG="$TMP/stub.log" \
  PATH="$STUB_DIR:$PATH" \
  run_hook "/trc.specify X"
# Gate 4 exits 0 silently when no graph and auto_bootstrap off. The hook
# should not have invoked graphify at all.
if [ -f "$TMP/stub.log" ]; then
  echo "FAIL: hook invoked graphify when no graph existed and auto_bootstrap=off"
  cat "$TMP/stub.log"
  exit 1
fi

# ── Happy path: flag on, graphify stub, graph exists → fire-and-forget ─────
# The hook delegates to `tricycle graphify refresh`. Put the real CLI where
# the hook expects it: $REPO_ROOT/bin/tricycle.
mkdir -p "$TMP/bin"
ln -sf "$REPO_ROOT/bin/tricycle" "$TMP/bin/tricycle"

mkdir -p "$TMP/graphify-out"
echo '{"nodes":[],"edges":[]}' > "$TMP/graphify-out/graph.json"
: > "$TMP/stub.log"
TMP_STUB_LOG="$TMP/stub.log" \
  PATH="$STUB_DIR:$PATH" \
  run_hook "/trc.specify Happy path"
# The hook delegates to `tricycle graphify refresh`, which itself
# backgrounds the graphify command. Give it a moment to spawn, then
# confirm the refresh pid file exists.
sleep 1
[ -f "$TMP/graphify-out/.refresh.pid" ] \
  || { echo "FAIL (happy path): .refresh.pid not written"; ls -la "$TMP/graphify-out"; exit 1; }

echo "graphify-hook-gating: OK"
