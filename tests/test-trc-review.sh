#!/usr/bin/env bash
set -euo pipefail

# test-trc-review.sh — Structural smoke tests for /trc.review.
#
# This file tests the shape of the command package — profile files present,
# frontmatter valid, cache helper works, command markdown references the
# documented contracts. The command itself is an agent-interpreted markdown
# file, so end-to-end evaluation is covered by the manual quickstart pass
# (Phase 9 T059), not by this bash suite.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

run_test() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  ✓ $name"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $name"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() { [ -f "$1" ]; }
assert_dir_exists() { [ -d "$1" ]; }
assert_grep() { grep -q "$2" "$1"; }
assert_exit_0() { "$@" >/dev/null 2>&1; }
assert_exit_nonzero() { ! "$@" >/dev/null 2>&1; }

echo ""
echo "trc.review command"
echo "=================="

# ── Command file ──────────────────────────────────────────────────────────

echo ""
echo "Command file:"

run_test "core/commands/trc.review.md exists" \
  assert_file_exists "$REPO_ROOT/core/commands/trc.review.md"

run_test "trc.review.md has YAML frontmatter" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" "^description:"

run_test "trc.review.md documents PR reference normalization" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" "expected PR number"

run_test "trc.review.md documents --prompt error message" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" "non-empty argument"

run_test "trc.review.md documents gh preflight error" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" "requires the GitHub CLI"

run_test "trc.review.md documents Unknown profile error" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" 'Unknown profile'

run_test "trc.review.md documents Unknown source error" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" 'Unknown source'

run_test "trc.review.md references empty-diff variant" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" "No reviewable changes"

run_test "trc.review.md references workflow.blocks.review.skills" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" "workflow.blocks.review.skills"

run_test "trc.review.md references empty-diff detection" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" "EMPTY_DIFF"

run_test "trc.review.md mentions --post confirmation gate" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" 'Post review findings to PR'

run_test "trc.review.md honors review.post_to_pr config flag (TRI-29)" \
  assert_grep "$REPO_ROOT/core/commands/trc.review.md" "review.post_to_pr: true"

run_test "trc.review.md does NOT call post_to_pr 'reserved' (TRI-29)" bash -c "
  ! grep -q 'reserved; not read in this version' '$REPO_ROOT/core/commands/trc.review.md'
"

run_test "config-schema.md does NOT call post_to_pr 'reserved' (TRI-29)" bash -c "
  ! grep -q 'Reserved; not read in this ticket' '$REPO_ROOT/specs/TRI-28-trc-review-command/contracts/config-schema.md'
"

# ── Bundled profiles ──────────────────────────────────────────────────────

echo ""
echo "Bundled profiles:"

PROFILE_DIR="$REPO_ROOT/core/commands/trc.review/profiles"

run_test "profiles directory exists" assert_dir_exists "$PROFILE_DIR"

for p in quality style security complexity; do
  run_test "$p profile file exists" assert_file_exists "$PROFILE_DIR/$p.md"
  run_test "$p profile has YAML frontmatter with name" \
    assert_grep "$PROFILE_DIR/$p.md" "^name: $p$"
  run_test "$p profile has source attribution" \
    assert_grep "$PROFILE_DIR/$p.md" "^source:"
  run_test "$p profile has license field" \
    assert_grep "$PROFILE_DIR/$p.md" "license:"
  run_test "$p profile has severity guide" \
    assert_grep "$PROFILE_DIR/$p.md" "Severity guide"
done

run_test "quality profile cites google/eng-practices" \
  assert_grep "$PROFILE_DIR/quality.md" "google/eng-practices"

run_test "quality profile cites awesome-reviewers" \
  assert_grep "$PROFILE_DIR/quality.md" "baz-scm/awesome-reviewers"

run_test "style profile cites awesome-reviewers" \
  assert_grep "$PROFILE_DIR/style.md" "baz-scm/awesome-reviewers"

run_test "security profile cites awesome-reviewers" \
  assert_grep "$PROFILE_DIR/security.md" "baz-scm/awesome-reviewers"

run_test "complexity profile cites awesome-reviewers" \
  assert_grep "$PROFILE_DIR/complexity.md" "baz-scm/awesome-reviewers"

run_test "no profile cites pr-agent (AGPL-3.0 — excluded per research.md)" bash -c "
  ! grep -r 'qodo-ai/pr-agent' '$PROFILE_DIR' >/dev/null 2>&1
"

# ── Cache helper ──────────────────────────────────────────────────────────

echo ""
echo "Cache helper:"

CACHE="$REPO_ROOT/core/scripts/bash/review-cache.sh"

run_test "review-cache.sh exists and is executable" bash -c "[ -x '$CACHE' ]"

run_test "review-cache.sh path prints a path under .trc/cache/review-sources" bash -c "
  out=\$('$CACHE' path https://example.com/x.md)
  echo \"\$out\" | grep -q '\\.trc/cache/review-sources/[0-9a-f]*\\.md\$'
"

run_test "review-cache.sh path is deterministic" bash -c "
  a=\$('$CACHE' path https://example.com/x.md)
  b=\$('$CACHE' path https://example.com/x.md)
  [ \"\$a\" = \"\$b\" ]
"

run_test "review-cache.sh path differs per URL" bash -c "
  a=\$('$CACHE' path https://example.com/a.md)
  b=\$('$CACHE' path https://example.com/b.md)
  [ \"\$a\" != \"\$b\" ]
"

run_test "review-cache.sh path without URL exits non-zero" \
  assert_exit_nonzero "$CACHE" path

run_test "review-cache.sh unknown command exits non-zero" \
  assert_exit_nonzero "$CACHE" totallybogus

run_test "review-cache.sh ensure-dir creates the directory" bash -c "
  rm -rf '$REPO_ROOT/.trc/cache/review-sources.test'
  dir=\$('$CACHE' ensure-dir)
  [ -d \"\$dir\" ]
"

# ── Normalize helper ──────────────────────────────────────────────────────

echo ""
echo "Node normalize-pr-ref helper:"

NORM="$REPO_ROOT/core/scripts/node/normalize-pr-ref.js"

run_test "normalize-pr-ref.js exists" assert_file_exists "$NORM"

run_test "normalize-pr-ref.js exports normalizePrRef" bash -c "
  node -e \"
    const { normalizePrRef } = require('$NORM');
    if (typeof normalizePrRef !== 'function') process.exit(1);
    const r = normalizePrRef('42');
    if (!r.ok || r.number !== 42) process.exit(1);
  \"
"

# ── Config and runtime integration ────────────────────────────────────────

echo ""
echo "Config and runtime integration:"

run_test "tricycle.config.yml has review: block" \
  assert_grep "$REPO_ROOT/tricycle.config.yml" "^review:"

run_test "tricycle.config.yml has workflow.blocks.review entry" bash -c "
  awk '/^workflow:/{in_wf=1} in_wf && /^  blocks:/{in_bk=1} in_bk && /^    review:/{found=1; exit} /^[a-z]/ && NR>1 && !/^workflow:/{in_wf=0; in_bk=0} END{exit !found}' '$REPO_ROOT/tricycle.config.yml'
"

run_test "docs/reviews/.gitkeep exists so report dir is tracked" \
  assert_file_exists "$REPO_ROOT/docs/reviews/.gitkeep"

run_test ".trc/ is gitignored (covers .trc/cache/)" \
  assert_grep "$REPO_ROOT/.gitignore" "^\.trc/$"

# ── Contract alignment ────────────────────────────────────────────────────

echo ""
echo "Contract alignment:"

SPEC_DIR="$REPO_ROOT/specs/TRI-28-trc-review-command"

run_test "spec.md exists" assert_file_exists "$SPEC_DIR/spec.md"
run_test "plan.md exists" assert_file_exists "$SPEC_DIR/plan.md"
run_test "tasks.md exists" assert_file_exists "$SPEC_DIR/tasks.md"
run_test "contracts/command-args.md exists" assert_file_exists "$SPEC_DIR/contracts/command-args.md"
run_test "contracts/config-schema.md exists" assert_file_exists "$SPEC_DIR/contracts/config-schema.md"
run_test "contracts/report-schema.md exists" assert_file_exists "$SPEC_DIR/contracts/report-schema.md"
run_test "research.md exists" assert_file_exists "$SPEC_DIR/research.md"
run_test "data-model.md exists" assert_file_exists "$SPEC_DIR/data-model.md"
run_test "quickstart.md exists" assert_file_exists "$SPEC_DIR/quickstart.md"

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "=================="
echo "trc.review: $PASS passed, $FAIL failed, $TOTAL total"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
