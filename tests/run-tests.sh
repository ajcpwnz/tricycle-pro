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
run_test "creates constitution placeholder" assert_file_exists "$TMPDIR_INIT/init-single/.trc/memory/constitution.md"
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

run_test "generate claude-md omits push gating (now in block)" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  "'"$CLI"'" generate claude-md >/dev/null 2>&1
  ! grep -q "Push Gating" CLAUDE.md
'

run_test "push-deploy block exists in core/blocks/implement" bash -c '
  [ -f "'"$REPO_ROOT"'/core/blocks/implement/push-deploy.md" ]
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
  grep -q "Lint" CLAUDE.md &&
  grep -q "Worktree" CLAUDE.md
'

# ── Skills system ──

echo ""
echo "Skills system:"

run_test "init installs all 5 vendored skills" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  [ -d "$dir/.claude/skills/code-reviewer" ] &&
  [ -d "$dir/.claude/skills/tdd" ] &&
  [ -d "$dir/.claude/skills/debugging" ] &&
  [ -d "$dir/.claude/skills/document-writer" ] &&
  [ -d "$dir/.claude/skills/catholic" ]
'

run_test "each vendored skill has SKILL.md" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  for s in code-reviewer tdd debugging document-writer catholic; do
    [ -f "$dir/.claude/skills/$s/SKILL.md" ] || exit 1
  done
'

run_test "each vendored skill has SOURCE file" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  for s in code-reviewer tdd debugging document-writer catholic; do
    [ -f "$dir/.claude/skills/$s/SOURCE" ] || exit 1
  done
'

run_test "SOURCE file contains origin field" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  grep -q "^origin: " "$dir/.claude/skills/code-reviewer/SOURCE"
'

run_test "SOURCE file contains checksum field" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  grep -q "^checksum: " "$dir/.claude/skills/code-reviewer/SOURCE"
'

run_test "skills disable skips listed skills" bash -c '
  dir="'"$TMPDIR_INIT"'/init-disabled"
  mkdir -p "$dir" && cd "$dir"
  rm -rf .claude/skills
  source "'"$REPO_ROOT"'/bin/lib/yaml_parser.sh"
  source "'"$REPO_ROOT"'/bin/lib/helpers.sh"
  detect_sha256
  printf "project:\n  name: test\nskills:\n  disable:\n    - tdd\n    - document-writer\n" > tricycle.config.yml
  CONFIG_DATA=$(parse_yaml tricycle.config.yml)
  CWD="$PWD"
  LOCK_FILES=""
  install_skills "'"$REPO_ROOT"'/core/skills" ".claude/skills" >/dev/null 2>&1
  [ ! -d ".claude/skills/tdd" ] && [ ! -d ".claude/skills/document-writer" ] &&
  [ -d ".claude/skills/code-reviewer" ] && [ -d ".claude/skills/debugging" ]
'

run_test "skills list command exits 0" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  "'"$CLI"'" skills list >/dev/null 2>&1
'

run_test "skills list shows installed skills" bash -c '
  cd "'"$TMPDIR_INIT"'/init-single"
  output=$("'"$CLI"'" skills list 2>&1)
  echo "$output" | grep -q "code-reviewer" &&
  echo "$output" | grep -q "catholic"
'

run_test "catholic skill has valid SKILL.md" bash -c '
  [ -f "'"$REPO_ROOT"'/core/skills/catholic/SKILL.md" ] &&
  head -5 "'"$REPO_ROOT"'/core/skills/catholic/SKILL.md" | grep -q "name: catholic"
'

run_test "catholic skill has SOURCE file" bash -c '
  [ -f "'"$REPO_ROOT"'/core/skills/catholic/SOURCE" ] &&
  grep -q "^origin: " "'"$REPO_ROOT"'/core/skills/catholic/SOURCE"
'

run_test "catholic block exists with correct frontmatter" bash -c '
  f="'"$REPO_ROOT"'/core/blocks/optional/specify/catholic.md"
  [ -f "$f" ] &&
  head -10 "$f" | grep -q "order: 1" &&
  head -10 "$f" | grep -q "required: false" &&
  head -10 "$f" | grep -q "default_enabled: false"
'

run_test "help text includes skills command" bash -c '
  "'"$CLI"'" --help 2>&1 | grep -q "skills list"
'

# ── Branch naming styles ──

echo ""
echo "Branch naming styles:"

CREATE_SCRIPT="$REPO_ROOT/core/scripts/bash/create-new-feature.sh"

run_test "feature-name style produces slug-only branch" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add dark mode toggle" --style feature-name --short-name "dark-mode" --json 2>/dev/null)
  echo "$out" | grep -q "\"BRANCH_NAME\":\"dark-mode\""
  rm -rf "$dir"
'

run_test "default style without flag is ordered" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add something" --short-name "something" --json 2>/dev/null)
  echo "$out" | grep -qE "\"BRANCH_NAME\":\"[0-9]{3}-something\""
  rm -rf "$dir"
'

run_test "issue-number style with explicit issue" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add export" --style issue-number --issue TRI-042 --short-name "export" --json 2>/dev/null)
  echo "$out" | grep -q "\"BRANCH_NAME\":\"TRI-042-export\""
  rm -rf "$dir"
'

run_test "issue-number style extracts from description" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "TRI-042 Add export feature" --style issue-number --prefix TRI --short-name "export" --json 2>/dev/null)
  echo "$out" | grep -q "\"BRANCH_NAME\":\"TRI-042-export\""
  rm -rf "$dir"
'

run_test "issue-number style exits 2 when no issue found" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && mkdir -p specs
  "'"$CREATE_SCRIPT"'" "Add export" --style issue-number --short-name "export" --json >/dev/null 2>&1
  [ $? -eq 2 ]
  rm -rf "$dir"
'

run_test "ordered style produces numbered branch" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add notifications" --style ordered --short-name "notifications" --json 2>/dev/null)
  echo "$out" | grep -qE "\"BRANCH_NAME\":\"[0-9]{3}-notifications\""
  rm -rf "$dir"
'

# ── --no-checkout flag ──

echo ""
echo "--no-checkout flag:"

run_test "--no-checkout creates branch without checking it out" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && git commit --allow-empty -m "init" -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style ordered --short-name "test-noco" --json --no-checkout 2>/dev/null)
  git branch --list | grep -q "001-test-noco" || exit 1
  current=$(git rev-parse --abbrev-ref HEAD)
  [ "$current" != "001-test-noco" ] || exit 1
  rm -rf "$dir"
'

run_test "--no-checkout does not create spec directory" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && git commit --allow-empty -m "init" -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style ordered --short-name "test-noco2" --json --no-checkout 2>/dev/null)
  [ ! -d specs/001-test-noco2 ] || exit 1
  rm -rf "$dir"
'

run_test "--no-checkout still outputs valid JSON" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && git commit --allow-empty -m "init" -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style ordered --short-name "test-noco3" --json --no-checkout 2>/dev/null)
  echo "$out" | grep -q "\"BRANCH_NAME\":\"001-test-noco3\"" || exit 1
  echo "$out" | grep -q "\"SPEC_FILE\":" || exit 1
  rm -rf "$dir"
'

run_test "without --no-checkout still checks out branch (backwards compat)" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && git commit --allow-empty -m "init" -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style ordered --short-name "test-compat" --json 2>/dev/null)
  current=$(git rev-parse --abbrev-ref HEAD)
  [ "$current" = "001-test-compat" ] || exit 1
  [ -d specs/001-test-compat ] || exit 1
  rm -rf "$dir"
'

# ── Summary ──

echo ""
echo "===================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
