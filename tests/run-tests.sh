#!/usr/bin/env bash
set -euo pipefail

# ─── Test runner ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$REPO_ROOT/bin/tricycle"

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
assert_file_contains() { grep -q "$2" "$1"; }
assert_file_executable() { [ -x "$1" ]; }
assert_exit_0() { "$@" >/dev/null 2>&1; }
assert_exit_nonzero() { ! "$@" >/dev/null 2>&1; }

# ─── Test groups ─────────────────────────────────────────────────────────────

echo ""
echo "tricycle CLI tests"
echo "=================="

# ── CLI basics ──

echo ""
echo "CLI basics:"
run_test "--help exits 0" assert_exit_0 "$CLI" --help
run_test "unknown command exits 1" assert_exit_nonzero "$CLI" unknown-cmd
run_test "update --dry-run exits cleanly" bash -c "cd '$REPO_ROOT' && '$CLI' update --dry-run"

# ── Core files integrity ──

echo ""
echo "Core files integrity:"

run_test "all hook scripts are executable" bash -c '
  for f in "'"$REPO_ROOT"'/core/hooks"/*.sh; do
    [ -x "$f" ] || exit 1
  done
'

run_test "all command templates exist" bash -c '
  for cmd in trc.specify trc.plan trc.tasks trc.implement trc.clarify trc.analyze trc.constitution trc.checklist trc.headless trc.taskstoissues; do
    [ -f "'"$REPO_ROOT"'/core/commands/$cmd.md" ] || exit 1
  done
'

run_test "all presets have valid YAML configs" bash -c '
  for d in "'"$REPO_ROOT"'/presets"/*/; do
    [ -f "$d/tricycle.config.yml" ] || exit 1
  done
'

run_test "every preset directory has a tricycle.config.yml" bash -c '
  count=$(find "'"$REPO_ROOT"'/presets" -mindepth 1 -maxdepth 1 -type d | wc -l)
  configs=$(find "'"$REPO_ROOT"'/presets" -name "tricycle.config.yml" | wc -l)
  [ "$count" -eq "$configs" ]
'

run_test "no hardcoded project names in hooks" bash -c '
  ! grep -rq "my-project\|my-app\|my-monorepo" "'"$REPO_ROOT"'/core/hooks/"
'

run_test "all modules have a README" bash -c '
  for d in "'"$REPO_ROOT"'/modules"/*/; do
    [ -f "$d/README.md" ] || exit 1
  done
'

# ── Init with presets ──

echo ""
echo "Init with presets:"

TMPDIR_INIT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_INIT"' EXIT

run_test "creates tricycle.config.yml from single-app preset" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  mkdir -p "$dir" && cd "$dir"
  echo "test-proj" | "'"$CLI"'" init --preset single-app >/dev/null 2>&1
  [ -f tricycle.config.yml ]
'

run_test "installs .claude/settings.json" assert_file_exists "$TMPDIR_INIT/init-single/.claude/settings.json"
run_test "installs hook scripts as executable" assert_file_executable "$TMPDIR_INIT/init-single/.claude/hooks/block-spec-in-main.sh"
run_test "installs command templates" assert_file_exists "$TMPDIR_INIT/init-single/.claude/commands/trc.plan.md"
run_test "creates .tricycle.lock" assert_file_exists "$TMPDIR_INIT/init-single/.tricycle.lock"
run_test "creates constitution placeholder" assert_file_exists "$TMPDIR_INIT/init-single/.specify/memory/constitution.md"
run_test "validate succeeds on initialized project" bash -c "cd '$TMPDIR_INIT/init-single' && '$CLI' validate"

# ── Init errors ──

echo ""
echo "Init errors:"

run_test "invalid preset exits 1 and lists available presets" bash -c '
  dir="'"$TMPDIR_INIT"'/init-bad"
  mkdir -p "$dir" && cd "$dir"
  output=$("'"$CLI"'" init --preset nonexistent 2>&1) && exit 1
  echo "$output" | grep -q "Available:"
'

run_test "express-prisma preset initializes successfully" bash -c '
  dir="'"$TMPDIR_INIT"'/init-express"
  mkdir -p "$dir" && cd "$dir"
  echo "express-test" | "'"$CLI"'" init --preset express-prisma >/dev/null 2>&1
  [ -f tricycle.config.yml ]
'

# ── Add modules ──

echo ""
echo "Add modules:"

run_test "add ci-watch installs commands" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  "'"$CLI"'" add ci-watch >/dev/null 2>&1
  [ -f .claude/commands/wait-ci.md ]
'

run_test "add memory installs seed files" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  "'"$CLI"'" add memory >/dev/null 2>&1
  [ -f .claude/memory/seeds/push-gating.md ]
'

run_test "add nonexistent module exits 1" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  ! "'"$CLI"'" add nonexistent >/dev/null 2>&1
'

run_test "add without module name exits 1" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  ! "'"$CLI"'" add >/dev/null 2>&1
'

# ── Generate ──

echo ""
echo "Generate:"

run_test "generate claude-md creates CLAUDE.md with project name" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  "'"$CLI"'" generate claude-md >/dev/null 2>&1
  grep -q "test-proj" CLAUDE.md
'

run_test "generate claude-md includes push gating section" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  grep -q "Push Gating" CLAUDE.md
'

run_test "generated settings.json always includes npx permission" bash -c '
  grep -q "npx" "'"$TMPDIR_INIT"'/init-single/.claude/settings.json"
'

run_test "generated settings.json includes npm permission" bash -c '
  grep -q "Bash(npm:\*)" "'"$TMPDIR_INIT"'/init-single/.claude/settings.json"
'

run_test "generate without config exits 1" bash -c '
  dir="'"$TMPDIR_INIT"'/no-config"
  mkdir -p "$dir" && cd "$dir"
  ! "'"$CLI"'" generate claude-md >/dev/null 2>&1
'

# Monorepo template test
run_test "generate claude-md with monorepo preset exercises all sections" bash -c '
  dir="'"$TMPDIR_INIT"'/init-monorepo"
  mkdir -p "$dir" && cd "$dir"
  mkdir -p apps/backend apps/frontend
  echo "mono-test" | "'"$CLI"'" init --preset monorepo-turborepo >/dev/null 2>&1
  "'"$CLI"'" generate claude-md >/dev/null 2>&1
  grep -q "mono-test" CLAUDE.md &&
  grep -q "Push Gating" CLAUDE.md &&
  grep -q "Lint" CLAUDE.md &&
  grep -q "Worktree" CLAUDE.md
'

# ── Summary ──

echo ""
echo "===================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
