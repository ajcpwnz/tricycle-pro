#!/usr/bin/env bash
# Tests for core/hooks/rename-on-kickoff.sh (TRI-31 UserPromptSubmit hook).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/core/hooks/rename-on-kickoff.sh"

[ -x "$HOOK" ] || { echo "FAIL: hook not executable at $HOOK"; exit 1; }

# Run the hook against a fixture repo so the branching-style config is
# controlled (tricycle-pro itself is issue-number/TRI which is fine but
# less portable).
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/core/scripts/bash" "$FIXTURE/.trc/scripts/bash"
cp "$REPO_ROOT/core/scripts/bash/derive-branch-name.sh" "$FIXTURE/core/scripts/bash/"
cp "$REPO_ROOT/core/scripts/bash/derive-branch-name.sh" "$FIXTURE/.trc/scripts/bash/"
cd "$FIXTURE"
git init -q -b main
git commit --allow-empty -q -m "seed"

write_config() {
    cat > tricycle.config.yml <<EOF
project:
  name: fixture
branching:
  style: $1
  prefix: $2
EOF
}

run_hook() {
    local prompt="$1"
    local session_title="${2:-}"
    CLAUDE_SESSION_TITLE="$session_title" \
        bash "$HOOK" < <(printf '{"prompt":%s}' "$(printf '%s' "$prompt" | jq -Rs .)")
}

title_of() {
    printf '%s' "$1" | jq -r '.hookSpecificOutput.sessionTitle // empty' 2>/dev/null
}

assert_eq() {
    local label="$1" actual="$2" expected="$3"
    if [ "$actual" != "$expected" ]; then
        echo "FAIL [$label]: expected '$expected', got '$actual'"; exit 1
    fi
}

# ── Case 1: non-kickoff prompt — no-op, empty stdout ─────────────────────
write_config issue-number TRI
out=$(run_hook "how do I fix this bug?")
assert_eq "non-kickoff" "$out" ""

# ── Case 2: /trc.specify with explicit issue in description ──────────────
out=$(run_hook "/trc.specify TRI-200 Add dark mode toggle")
assert_eq "specify issue-number explicit" "$(title_of "$out")" "TRI-200-dark-mode-toggle"

# ── Case 3: /trc.specify issue-number without ticket → empty stdout ──────
out=$(run_hook "/trc.specify Some feature without a ticket id")
assert_eq "specify issue-number no id" "$out" ""

# ── Case 4: /trc.specify feature-name style ──────────────────────────────
write_config feature-name ""
out=$(run_hook "/trc.specify Add notifications")
assert_eq "specify feature-name" "$(title_of "$out")" "notifications"

# ── Case 5: /trc.headless follows the same branch ────────────────────────
out=$(run_hook "/trc.headless Improve onboarding flow")
assert_eq "headless feature-name" "$(title_of "$out")" "improve-onboarding-flow"

# ── Case 6: /trc.chain range ─────────────────────────────────────────────
out=$(run_hook "/trc.chain TRI-300..TRI-302")
assert_eq "chain range" "$(title_of "$out")" "trc-chain-TRI-300..TRI-302"

# ── Case 7: /trc.chain list ──────────────────────────────────────────────
out=$(run_hook "/trc.chain TRI-100,TRI-103,POL-42")
assert_eq "chain list" "$(title_of "$out")" "trc-chain-TRI-100+2"

# ── Case 7b: /trc.chain arrow form (→ and ->) counts all tokens ──────────
out=$(run_hook "/trc.chain TRI-100 → TRI-103 → POL-42")
assert_eq "chain arrow unicode" "$(title_of "$out")" "trc-chain-TRI-100+2"
out=$(run_hook "/trc.chain TRI-100 -> TRI-103 -> POL-42 -> POL-43")
assert_eq "chain arrow ascii" "$(title_of "$out")" "trc-chain-TRI-100+3"

# ── Case 7c: emission carries hookEventName (CC validator requirement) ───
out=$(run_hook "/trc.chain TRI-100,TRI-103")
event=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
assert_eq "hookEventName present" "$event" "UserPromptSubmit"

# ── Case 8: /trc.chain singleton → still prefixed ────────────────────────
out=$(run_hook "/trc.chain TRI-100")
assert_eq "chain singleton" "$(title_of "$out")" "trc-chain-TRI-100+0"

# ── Case 9: idempotency — already matches → empty stdout ─────────────────
out=$(run_hook "/trc.chain TRI-300..TRI-302" "trc-chain-TRI-300..TRI-302")
assert_eq "chain idempotent" "$out" ""

# ── Case 10: leading whitespace tolerated ────────────────────────────────
out=$(run_hook "   /trc.chain TRI-400..TRI-401")
assert_eq "leading whitespace" "$(title_of "$out")" "trc-chain-TRI-400..TRI-401"

# ── Case 11: empty prompt → no-op ────────────────────────────────────────
out=$(run_hook "")
assert_eq "empty prompt" "$out" ""

# ── Case 12: cold-path timing budget — sanity bound ──────────────────────
write_config issue-number TRI
start=$(python3 -c 'import time; print(int(time.time()*1000))')
for _ in 1 2 3 4 5; do
    run_hook "/trc.specify TRI-999 Test speed" >/dev/null
done
end=$(python3 -c 'import time; print(int(time.time()*1000))')
elapsed=$((end - start))
per_call=$((elapsed / 5))
if [ "$per_call" -gt 500 ]; then
    echo "FAIL [timing]: avg ${per_call}ms per call exceeds 500ms budget"; exit 1
fi

cd - >/dev/null
echo "rename-hook: OK"
