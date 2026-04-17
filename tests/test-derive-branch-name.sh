#!/usr/bin/env bash
# Parity + contract test for core/scripts/bash/derive-branch-name.sh.
#
# Asserts the helper produces byte-identical branch names to
# create-new-feature.sh for every style/flag combo we care about, and that
# it has no side effects.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVE="$REPO_ROOT/core/scripts/bash/derive-branch-name.sh"
CREATE="$REPO_ROOT/core/scripts/bash/create-new-feature.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── Contract checks ────────────────────────────────────────────────────────

# Exit code 2 when issue-number requested without an ID or extractable pattern.
set +e
out=$(bash "$DERIVE" --style issue-number --prefix TRI --short-name "foo" "description with no id" 2>/dev/null)
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
    echo "FAIL: expected exit 2 on missing issue ID, got $rc"; exit 1
fi

# Single-line stdout, no trailing whitespace beyond one newline.
out=$(bash "$DERIVE" --style feature-name --short-name "hello world" "Hello World")
lines=$(printf '%s' "$out" | wc -l | tr -d ' ')
if [ "$lines" -ne 0 ]; then
    # wc -l counts newlines; printf without trailing \n has 0 newlines.
    # $() strips the single trailing newline, so we should see 0.
    echo "FAIL: derive output should be single-line; saw $lines newlines"; exit 1
fi

# No side effects: no new files under repo after running.
pre=$(find "$REPO_ROOT" -maxdepth 3 -type f -newer "$DERIVE" 2>/dev/null | wc -l | tr -d ' ')
bash "$DERIVE" --style feature-name --short-name "side-effect-test" "test" >/dev/null
post=$(find "$REPO_ROOT" -maxdepth 3 -type f -newer "$DERIVE" 2>/dev/null | wc -l | tr -d ' ')
if [ "$post" -gt "$pre" ]; then
    echo "FAIL: derive-branch-name.sh appears to have created files"; exit 1
fi

# ── Parity with create-new-feature.sh ─────────────────────────────────────

# Run create-new-feature.sh in a throwaway git repo fixture so it doesn't
# touch the main checkout. Compare BRANCH_NAME output for identical inputs.
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"
cd "$FIXTURE"
git init -q -b main
git commit --allow-empty -q -m "seed"

parity_case() {
    local label="$1"; shift
    local expected derived
    # Derive FIRST while the repo is clean — the helper reads local branch
    # state, so if we let create-new-feature.sh create a branch first the
    # ordered-style counter would jump. Then run the creator and compare
    # the branch name it produced.
    derived=$(bash "$DERIVE" "$@" 2>/dev/null)
    expected=$(bash "$CREATE" --json --no-checkout "$@" 2>/dev/null | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["BRANCH_NAME"])')
    if [ "$expected" != "$derived" ]; then
        echo "FAIL [$label]: parity mismatch"
        echo "  create-new-feature.sh: $expected"
        echo "  derive-branch-name.sh: $derived"
        echo "  flags: $*"
        exit 1
    fi
    # Cleanup the branch and any spec dir so the next case starts clean.
    git checkout -q main 2>/dev/null || true
    git branch -D "$expected" >/dev/null 2>&1 || true
    rm -rf "specs/$expected" 2>/dev/null || true
}

parity_case "feature-name basic"      --style feature-name --short-name "dark-mode" "Add dark mode"
parity_case "feature-name multi-word" --style feature-name --short-name "export csv users" "Export CSV for users"
parity_case "issue-number explicit"   --style issue-number --issue "TRI-42"  --prefix TRI --short-name "export-csv" "Add CSV export"
parity_case "issue-number extracted"  --style issue-number --prefix TRI --short-name "foo" "TRI-99 fix thing"
parity_case "issue-number lowercase"  --style issue-number --issue "tri-7"   --prefix TRI --short-name "slug" "Description"
parity_case "ordered first"           --style ordered --short-name "notifications" "Add notifications"
parity_case "ordered second"          --style ordered --short-name "profile" "Profile page"
parity_case "ordered --number"        --style ordered --number 42 --short-name "manual" "Manual number"

cd - >/dev/null

echo "derive-branch-name: OK"
