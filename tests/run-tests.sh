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
  for cmd in trc.plan trc.implement trc.constitution trc.chain trc.band trc.audit; do
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

# ── Command assembly ──

echo ""
echo "Command assembly:"

run_test "assembler builds trc.plan and trc.implement from blocks (tests/test-assemble-commands.sh)" \
  bash "$REPO_ROOT/tests/test-assemble-commands.sh"

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
run_test "installs hook scripts as executable" assert_file_executable "$TMPDIR_INIT/init-single/.claude/hooks/rename-on-kickoff.sh"
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

run_test "generate claude-md produces no awk errors on stderr" bash -c '
  dir="'"$TMPDIR_INIT"'/init-monorepo"
  cd "$dir"
  errors=$("'"$CLI"'" generate claude-md 2>&1 >/dev/null)
  [ -z "$errors" ]
'

run_test "generate claude-md for all presets succeeds without errors" bash -c '
  for preset in single-app express-prisma; do
    dir="'"$TMPDIR_INIT"'/gen-test-$preset"
    mkdir -p "$dir" && cd "$dir"
    echo "gen-$preset" | "'"$CLI"'" init --preset "$preset" >/dev/null 2>&1
    errors=$("'"$CLI"'" generate claude-md 2>&1 >/dev/null)
    [ -z "$errors" ] || exit 1
    grep -q "gen-$preset" CLAUDE.md || exit 1
  done
'

run_test "generated CLAUDE.md has no leftover template markers" bash -c '
  dir="'"$TMPDIR_INIT"'/init-monorepo"
  cd "$dir"
  ! grep -q "{{" CLAUDE.md
'

# ── SessionStart context hook ──

echo ""
echo "SessionStart context hook:"

run_test "generated settings.json includes SessionStart hook" bash -c '
  grep -q "SessionStart" "'"$TMPDIR_INIT"'/init-single/.claude/settings.json"
'

run_test "session-context hook is installed and executable" bash -c '
  [ -x "'"$TMPDIR_INIT"'/init-single/.claude/hooks/session-context.sh" ]
'

run_test ".session-context.conf is generated with constitution path" bash -c '
  [ -f "'"$TMPDIR_INIT"'/init-single/.claude/hooks/.session-context.conf" ] &&
  grep -q "constitution" "'"$TMPDIR_INIT"'/init-single/.claude/hooks/.session-context.conf"
'

run_test "session-context hook outputs valid JSON for populated constitution" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  printf "# My Constitution\n\nPrinciple I: Test everything.\n" > "$dir/.trc/memory/constitution.md"
  output=$(cd "$dir" && echo "{}" | bash .claude/hooks/session-context.sh 2>/dev/null)
  echo "$output" | grep -q "hookSpecificOutput"
'

run_test "session-context hook handles missing constitution gracefully" bash -c '
  dir=$(mktemp -d)
  mkdir -p "$dir/.claude/hooks"
  printf "# Auto-generated\nnonexistent-file.md\n" > "$dir/.claude/hooks/.session-context.conf"
  cd "$dir" && git init -q
  output=$(echo "{}" | bash "'"$TMPDIR_INIT"'/init-single/.claude/hooks/session-context.sh" 2>/dev/null)
  [ $? -eq 0 ] && [ -z "$output" ]
  rm -rf "$dir"
'

run_test "session-context hook skips placeholder constitution" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  printf "# Project Constitution\n\n_Run \`/trc.constitution\` to populate this file._\n" > "$dir/.trc/memory/constitution.md"
  output=$(cd "$dir" && echo "{}" | bash .claude/hooks/session-context.sh 2>/dev/null)
  [ -z "$output" ]
'

run_test "session-context hook includes extra configured files" bash -c '
  dir=$(mktemp -d) && cd "$dir" && git init -q
  echo "test-ctx" | "'"$CLI"'" init --preset single-app >/dev/null 2>&1
  mkdir -p docs
  printf "# Architecture\n\nWe use microservices.\n" > docs/architecture.md
  printf "# My Constitution\n\nPrinciple I: Test.\n" > .trc/memory/constitution.md
  # Add extra file to config
  printf "\ncontext:\n  session_start:\n    constitution: true\n    files:\n      - \"docs/architecture.md\"\n" >> tricycle.config.yml
  "'"$CLI"'" generate settings >/dev/null 2>&1
  output=$(echo "{}" | bash .claude/hooks/session-context.sh 2>/dev/null)
  echo "$output" | grep -q "Architecture" && echo "$output" | grep -q "Constitution"
  rm -rf "$dir"
'

run_test "session-context hook skips missing configured files" bash -c '
  dir=$(mktemp -d) && cd "$dir" && git init -q
  echo "test-ctx" | "'"$CLI"'" init --preset single-app >/dev/null 2>&1
  printf "# My Constitution\n\nPrinciple I: Test.\n" > .trc/memory/constitution.md
  printf "\ncontext:\n  session_start:\n    constitution: true\n    files:\n      - \"nonexistent.md\"\n" >> tricycle.config.yml
  "'"$CLI"'" generate settings >/dev/null 2>&1
  output=$(echo "{}" | bash .claude/hooks/session-context.sh 2>/dev/null)
  echo "$output" | grep -q "Constitution"
  rm -rf "$dir"
'

run_test "SessionStart hook has no matcher (fires on all events)" bash -c '
  section=$(grep -A5 "SessionStart" "'"$TMPDIR_INIT"'/init-single/.claude/settings.json")
  ! echo "$section" | grep -q "matcher"
'

run_test "SessionStart omitted when constitution false and no files" bash -c '
  dir=$(mktemp -d) && cd "$dir" && git init -q
  echo "test-ctx" | "'"$CLI"'" init --preset single-app >/dev/null 2>&1
  printf "\ncontext:\n  session_start:\n    constitution: false\n" >> tricycle.config.yml
  "'"$CLI"'" generate settings >/dev/null 2>&1
  ! grep -q "SessionStart" .claude/settings.json
  rm -rf "$dir"
'

# ── Skills system ──

echo ""
echo "Skills system:"

run_test "init installs all vendored skills" bash -c '
  dir="'"$TMPDIR_INIT"'/init-single"
  [ -d "$dir/.claude/skills/ste-short" ] &&
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
  f="'"$REPO_ROOT"'/core/blocks/optional/plan/catholic.md"
  [ -f "$f" ] &&
  head -10 "$f" | grep -q "step: plan" &&
  head -10 "$f" | grep -q "order: 1" &&
  head -10 "$f" | grep -q "required: false" &&
  head -10 "$f" | grep -q "default_enabled: false"
'

run_test "help text includes skills command" bash -c '
  "'"$CLI"'" --help 2>&1 | grep -q "skills list"
'

run_test "audit command exists with valid frontmatter" bash -c '
  f="'"$REPO_ROOT"'/core/commands/trc.audit.md"
  [ -f "$f" ] &&
  head -5 "$f" | grep -q "description:" &&
  grep -q "Constitution" "$f" &&
  grep -q "docs/audits/" "$f"
'

run_test "linear-audit skill has valid SKILL.md" bash -c '
  [ -f "'"$REPO_ROOT"'/core/skills/linear-audit/SKILL.md" ] &&
  head -5 "'"$REPO_ROOT"'/core/skills/linear-audit/SKILL.md" | grep -q "name: linear-audit"
'

run_test "linear-audit skill has SOURCE file" bash -c '
  [ -f "'"$REPO_ROOT"'/core/skills/linear-audit/SOURCE" ] &&
  grep -q "^origin: " "'"$REPO_ROOT"'/core/skills/linear-audit/SOURCE"
'

run_test "docs/audits directory exists" bash -c '
  [ -d "'"$REPO_ROOT"'/docs/audits" ]
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
  echo "$out" | grep -q "\"FEATURE_NUM\":\"001\"" || exit 1
  ! echo "$out" | grep -q "SPEC_FILE" || exit 1
  rm -rf "$dir"
'

run_test "without --no-checkout the script checks out the new branch" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && git commit --allow-empty -m "init" -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style ordered --short-name "test-compat" --json 2>/dev/null)
  current=$(git rev-parse --abbrev-ref HEAD)
  [ "$current" = "001-test-compat" ] || exit 1
  [ ! -e specs/001-test-compat ] || exit 1
  rm -rf "$dir"
'

# ── --provision-worktree flag (TRI-26) ──

echo ""
echo "--provision-worktree flag:"

run_test "--provision-worktree happy path installs deps and runs setup script" bash -c '
  parent=$(mktemp -d)
  main=$(
    mkdir -p "$parent/main/scripts" "$parent/main/.trc/templates"
    cd "$parent/main"
    git init -q >/dev/null
    npm init -y >/dev/null 2>&1
    cat > tricycle.config.yml <<YAML
project:
  name: "provdemo"
  package_manager: "npm"
worktree:
  enabled: true
  setup_script: scripts/worktree-setup.sh
  env_copy:
    - .env.local
YAML
    cat > scripts/worktree-setup.sh <<EOS
#!/usr/bin/env bash
set -e
touch .env.local
EOS
    chmod +x scripts/worktree-setup.sh
    printf "# Spec Template\n" > .trc/templates/spec-template.md
    git add -A >/dev/null
    git commit -q -m seed >/dev/null
    pwd
  )
  cd "$main"
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style feature-name --short-name "demo" --json --provision-worktree 2>&1)
  echo "$out" | grep -q "\"WORKTREE_PATH\":" || { echo "missing WORKTREE_PATH in: $out" >&2; rm -rf "$parent"; exit 1; }
  wt="$parent/provdemo-demo"
  [ -d "$wt" ] || { echo "worktree dir missing: $wt" >&2; rm -rf "$parent"; exit 1; }
  [ -f "$wt/.env.local" ] || { echo ".env.local missing" >&2; rm -rf "$parent"; exit 1; }
  [ -d "$wt/node_modules" ] || [ -f "$wt/package-lock.json" ] || { echo "install never ran" >&2; rm -rf "$parent"; exit 1; }
  [ -d "$wt/.trc" ] || { echo ".trc not copied" >&2; rm -rf "$parent"; exit 1; }
  [ ! -e "$wt/specs/demo" ] || { echo "a per-branch spec dir was created" >&2; rm -rf "$parent"; exit 1; }
  rm -rf "$parent"
'

run_test "--provision-worktree with no setup_script or env_copy is no-op (still exits 0)" bash -c '
  parent=$(mktemp -d)
  main="$parent/main"
  mkdir -p "$main/.trc/templates"
  cd "$main"
  git init -q
  npm init -y >/dev/null 2>&1
  cat > tricycle.config.yml <<YAML
project:
  name: "bareproj"
  package_manager: "npm"
worktree:
  enabled: true
YAML
  printf "# Spec Template\n" > .trc/templates/spec-template.md
  git add -A && git commit -q -m seed
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style feature-name --short-name "bare" --json --provision-worktree 2>&1) || { echo "failed: $out" >&2; rm -rf "$parent"; exit 1; }
  [ -d "$parent/bareproj-bare" ] || { rm -rf "$parent"; exit 1; }
  rm -rf "$parent"
'

run_test "--provision-worktree fails with exit 12 when setup_script missing" bash -c '
  parent=$(mktemp -d)
  main="$parent/main"
  mkdir -p "$main/.trc/templates"
  cd "$main"
  git init -q
  npm init -y >/dev/null 2>&1
  cat > tricycle.config.yml <<YAML
project:
  name: "missing"
  package_manager: "npm"
worktree:
  enabled: true
  setup_script: scripts/does-not-exist.sh
YAML
  printf "# Spec Template\n" > .trc/templates/spec-template.md
  git add -A && git commit -q -m seed
  set +e
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style feature-name --short-name "m" --json --provision-worktree 2>&1)
  rc=$?
  set -e
  [ "$rc" -eq 12 ] || { echo "expected exit 12 got $rc" >&2; rm -rf "$parent"; exit 1; }
  echo "$out" | grep -q "does not exist in worktree root" || { echo "wrong error: $out" >&2; rm -rf "$parent"; exit 1; }
  rm -rf "$parent"
'

run_test "--provision-worktree fails with exit 14 when setup_script exits non-zero" bash -c '
  parent=$(mktemp -d)
  main="$parent/main"
  mkdir -p "$main/scripts" "$main/.trc/templates"
  cd "$main"
  git init -q
  npm init -y >/dev/null 2>&1
  cat > tricycle.config.yml <<YAML
project:
  name: "fails"
  package_manager: "npm"
worktree:
  enabled: true
  setup_script: scripts/fail.sh
YAML
  cat > scripts/fail.sh <<EOS
#!/usr/bin/env bash
exit 7
EOS
  chmod +x scripts/fail.sh
  printf "# Spec Template\n" > .trc/templates/spec-template.md
  git add -A && git commit -q -m seed
  set +e
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style feature-name --short-name "f" --json --provision-worktree 2>&1)
  rc=$?
  set -e
  [ "$rc" -eq 14 ] || { echo "expected 14 got $rc: $out" >&2; rm -rf "$parent"; exit 1; }
  echo "$out" | grep -q "exited 7" || { echo "wrong err: $out" >&2; rm -rf "$parent"; exit 1; }
  rm -rf "$parent"
'

run_test "--provision-worktree fails with exit 15 when env_copy path missing" bash -c '
  parent=$(mktemp -d)
  main="$parent/main"
  mkdir -p "$main/scripts" "$main/.trc/templates"
  cd "$main"
  git init -q
  npm init -y >/dev/null 2>&1
  cat > tricycle.config.yml <<YAML
project:
  name: "ec"
  package_manager: "npm"
worktree:
  enabled: true
  setup_script: scripts/empty.sh
  env_copy:
    - .env.notcreated
    - also-missing
YAML
  cat > scripts/empty.sh <<EOS
#!/usr/bin/env bash
exit 0
EOS
  chmod +x scripts/empty.sh
  printf "# Spec Template\n" > .trc/templates/spec-template.md
  git add -A && git commit -q -m seed
  set +e
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style feature-name --short-name "e" --json --provision-worktree 2>&1)
  rc=$?
  set -e
  [ "$rc" -eq 15 ] || { echo "expected 15 got $rc: $out" >&2; rm -rf "$parent"; exit 1; }
  echo "$out" | grep -q "env_copy paths missing after setup" || { echo "wrong err: $out" >&2; rm -rf "$parent"; exit 1; }
  echo "$out" | grep -q ".env.notcreated" || { echo "missing first path in err" >&2; rm -rf "$parent"; exit 1; }
  echo "$out" | grep -q "also-missing" || { echo "missing second path in err" >&2; rm -rf "$parent"; exit 1; }
  rm -rf "$parent"
'

run_test "--provision-worktree fails with exit 11 when package manager not on PATH" bash -c '
  parent=$(mktemp -d)
  main="$parent/main"
  mkdir -p "$main/.trc/templates"
  cd "$main"
  git init -q
  npm init -y >/dev/null 2>&1
  cat > tricycle.config.yml <<YAML
project:
  name: "nopm"
  package_manager: "does-not-exist-pm-xyz"
worktree:
  enabled: true
YAML
  printf "# Spec Template\n" > .trc/templates/spec-template.md
  git add -A && git commit -q -m seed
  set +e
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style feature-name --short-name "n" --json --provision-worktree 2>&1)
  rc=$?
  set -e
  [ "$rc" -eq 11 ] || { echo "expected 11 got $rc: $out" >&2; rm -rf "$parent"; exit 1; }
  echo "$out" | grep -q "not found on PATH" || { echo "wrong err: $out" >&2; rm -rf "$parent"; exit 1; }
  rm -rf "$parent"
'

run_test "--provision-worktree respects project.package_manager (pnpm stub)" bash -c '
  parent=$(mktemp -d)
  main="$parent/main"
  stubdir="$parent/stub-bin"
  mkdir -p "$main/.trc/templates" "$stubdir"
  # Stub "pnpm" that records its invocation and exits 0
  cat > "$stubdir/pnpm" <<EOS
#!/usr/bin/env bash
echo "PNPM_CALLED \$*" > "$parent/pnpm-marker"
exit 0
EOS
  chmod +x "$stubdir/pnpm"
  export PATH="$stubdir:$PATH"
  cd "$main"
  git init -q
  npm init -y >/dev/null 2>&1
  cat > tricycle.config.yml <<YAML
project:
  name: "pnp"
  package_manager: "pnpm"
worktree:
  enabled: true
YAML
  printf "# Spec Template\n" > .trc/templates/spec-template.md
  git add -A && git commit -q -m seed
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style feature-name --short-name "p" --json --provision-worktree 2>&1) || { echo "failed: $out" >&2; rm -rf "$parent"; exit 1; }
  grep -q "PNPM_CALLED install" "$parent/pnpm-marker" || { echo "pnpm stub not invoked with install" >&2; rm -rf "$parent"; exit 1; }
  rm -rf "$parent"
'

run_test "--provision-worktree defaults to npm when project.package_manager is unset" bash -c '
  parent=$(mktemp -d)
  main="$parent/main"
  stubdir="$parent/stub-bin"
  mkdir -p "$main/.trc/templates" "$stubdir"
  # Stub "npm" that records invocation; project init still needs real npm so we put the stub later in PATH.
  cat > "$stubdir/npm" <<EOS
#!/usr/bin/env bash
if [ "\$1" = "install" ]; then
  echo "NPM_DEFAULT_CALLED" > "$parent/npm-marker"
  exit 0
fi
exec /usr/bin/env -i PATH=/usr/bin:/bin npm "\$@"
EOS
  chmod +x "$stubdir/npm"
  cd "$main"
  git init -q
  # Use the REAL npm for init (via absolute-path lookup), not the stub
  REAL_NPM=$(command -v npm)
  "$REAL_NPM" init -y >/dev/null 2>&1
  cat > tricycle.config.yml <<YAML
project:
  name: "defpm"
worktree:
  enabled: true
YAML
  printf "# Spec Template\n" > .trc/templates/spec-template.md
  git add -A && git commit -q -m seed
  export PATH="$stubdir:$PATH"
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style feature-name --short-name "d" --json --provision-worktree 2>&1) || { echo "failed: $out" >&2; rm -rf "$parent"; exit 1; }
  [ -f "$parent/npm-marker" ] || { echo "default npm stub not invoked" >&2; rm -rf "$parent"; exit 1; }
  rm -rf "$parent"
'

run_test "without --provision-worktree no WORKTREE_PATH key in JSON (backwards compat)" bash -c '
  dir=$(mktemp -d)
  cd "$dir" && git init -q && git commit --allow-empty -m "init" -q && mkdir -p specs
  out=$("'"$CREATE_SCRIPT"'" "Add feature" --style ordered --short-name "test-bc" --json 2>/dev/null)
  echo "$out" | grep -q "\"BRANCH_NAME\":" || exit 1
  ! echo "$out" | grep -q "WORKTREE_PATH" || exit 1
  rm -rf "$dir"
'

# ── Status command ──

echo ""
echo "Status command:"

STATUS_FX=$(mktemp -d)
mkdir -p "$STATUS_FX/docs/specs"
printf 'project:\n  name: s\n' > "$STATUS_FX/tricycle.config.yml"
printf '# Add export\n\nSource: X-1 · Status: validated\n\n## Checklist\n\n- [x] a\n- [ ] b\n' > "$STATUS_FX/docs/specs/X-1.md"
printf '# Fix login\n\nSource: X-2 · Status: draft\n\n## Checklist\n\n- [ ] a\n' > "$STATUS_FX/docs/specs/X-2.md"

run_test "status --help mentions status" bash -c '
  "'"$CLI"'" --help 2>&1 | grep -q "tricycle status"
'

run_test "status lists every spec with its status and checklist progress" bash -c '
  out=$(cd "'"$STATUS_FX"'" && "'"$CLI"'" status)
  echo "$out" | grep -E "X-1 .*Add export .*validated .*1/2" >/dev/null &&
  echo "$out" | grep -E "X-2 .*Fix login .*draft .*0/1" >/dev/null
'

run_test "status --json outputs parseable JSON" bash -c '
  cd "'"$STATUS_FX"'" && "'"$CLI"'" status --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert {x[\"id\"] for x in d} == {\"X-1\",\"X-2\"}; assert [x for x in d if x[\"id\"]==\"X-1\"][0][\"done\"] == 1"
'

run_test "status filter by spec id" bash -c '
  out=$(cd "'"$STATUS_FX"'" && "'"$CLI"'" status X-2)
  echo "$out" | grep -q "X-2" && ! echo "$out" | grep -q "X-1"
'

run_test "status with no specs points to /trc.plan" bash -c '
  d=$(mktemp -d); printf "project:\n  name: e\n" > "$d/tricycle.config.yml"
  (cd "$d" && "'"$CLI"'" status) | grep -q "/trc.plan"
'

run_test "status with a tracker store says where specs live" bash -c '
  d=$(mktemp -d); printf "project:\n  name: e\nspec:\n  store: linear\n" > "$d/tricycle.config.yml"
  (cd "$d" && "'"$CLI"'" status) | grep -q "spec.store: linear"
'

# ── chain-run.sh (TRI-27) ──

echo ""
echo "chain-run.sh (TRI-27):"

run_test "e2e happy path (tests/test-chain-run-e2e-happy.sh)" bash "$REPO_ROOT/tests/test-chain-run-e2e-happy.sh"
run_test "parallel scheduler: slot cap, dependency gating, cycles (tests/test-chain-run-parallel.sh)" bash "$REPO_ROOT/tests/test-chain-run-parallel.sh"
run_test "chain and band reconcilers classify workers (tests/test-reconcile.sh)" bash "$REPO_ROOT/tests/test-reconcile.sh"
run_test "branch-name parsers keep quotes and refuse blank input (tests/test-feature-description.sh)" bash "$REPO_ROOT/tests/test-feature-description.sh"
run_test "update installs only the core hooks settings register (tests/test-update-core-hooks-wanted.sh)" bash "$REPO_ROOT/tests/test-update-core-hooks-wanted.sh"
run_test "update is byte-exact, keeps the lock, and is a no-op twice (tests/test-update-idempotent.sh)" bash "$REPO_ROOT/tests/test-update-idempotent.sh"
run_test "update keeps module files, regenerates settings, deletes emptied dirs (tests/test-update-keeps-module-files.sh)" bash "$REPO_ROOT/tests/test-update-keeps-module-files.sh"
run_test "generated .gitignore ignores chain and band run state (tests/test-gitignore-run-state.sh)" bash "$REPO_ROOT/tests/test-gitignore-run-state.sh"
run_test "e2e stop-on-failure (tests/test-chain-run-e2e-failure.sh)" bash "$REPO_ROOT/tests/test-chain-run-e2e-failure.sh"
run_test "e2e resume flow (tests/test-chain-run-e2e-resume.sh)" bash "$REPO_ROOT/tests/test-chain-run-e2e-resume.sh"
run_test "epic brief copy + missing (tests/test-chain-run-epic-brief.sh)" bash "$REPO_ROOT/tests/test-chain-run-epic-brief.sh"

run_test "trc.chain command template exists and has description" bash -c '
  [ -f "'"$REPO_ROOT"'/core/commands/trc.chain.md" ] || exit 1
  grep -q "^description:" "'"$REPO_ROOT"'/core/commands/trc.chain.md"
'

run_test "chain-run.sh is executable" test -x "$REPO_ROOT/core/scripts/bash/chain-run.sh"

run_test "specs/.chain-runs/ is gitignored" bash -c '
  cd "'"$REPO_ROOT"'" && grep -q "specs/.chain-runs/" .gitignore
'

# ── chain-run.sh (TRI-30) ──

echo ""
echo "chain-run.sh (TRI-30):"

run_test "FR-013 no pause-relay refs in trc.chain.md" bash "$REPO_ROOT/tests/test-chain-run-no-pause-relay.sh"

run_test "trc.chain.md contract rules present (tests/test-chain-md-contract.sh)" \
  bash "$REPO_ROOT/tests/test-chain-md-contract.sh"

run_test "tricycle update adopts unmanaged files (tests/test-tricycle-update-adopt.sh)" \
  bash "$REPO_ROOT/tests/test-tricycle-update-adopt.sh"

run_test "update survives skipped files + skill SOURCE stays clean (tests/test-update-skip-resilience.sh)" \
  bash "$REPO_ROOT/tests/test-update-skip-resilience.sh"

run_test "tricycle update-self exec-finalize avoids self-replace race (tests/test-update-self-exec.sh)" \
  bash "$REPO_ROOT/tests/test-update-self-exec.sh"

# ── band-run.sh (/trc.band) ──

echo ""
echo "band-run.sh (/trc.band):"

run_test "e2e happy path (tests/test-band-run-e2e-happy.sh)" bash "$REPO_ROOT/tests/test-band-run-e2e-happy.sh"

run_test "error paths + scheduling guards (tests/test-band-run-errors.sh)" \
  bash "$REPO_ROOT/tests/test-band-run-errors.sh"

run_test "trc.band command template exists and has description" bash -c '
  [ -f "'"$REPO_ROOT"'/core/commands/trc.band.md" ] || exit 1
  grep -q "^description:" "'"$REPO_ROOT"'/core/commands/trc.band.md"
'

run_test "band-run.sh is executable" test -x "$REPO_ROOT/core/scripts/bash/band-run.sh"

run_test "specs/.band-runs/ is gitignored" bash -c '
  cd "'"$REPO_ROOT"'" && grep -q "specs/.band-runs/" .gitignore
'

run_test "trc.band.md contract rules present (tests/test-band-md-contract.sh)" \
  bash "$REPO_ROOT/tests/test-band-md-contract.sh"

run_test "recon template contract (tests/test-recon-template.sh)" \
  bash "$REPO_ROOT/tests/test-recon-template.sh"

# ── Session rename on kickoff (TRI-31) ──

echo ""
echo "Session rename hook (TRI-31):"

run_test "derive-branch-name parity with create-new-feature (tests/test-derive-branch-name.sh)" \
  bash "$REPO_ROOT/tests/test-derive-branch-name.sh"

run_test "rename-on-kickoff hook behavior (tests/test-rename-hook.sh)" \
  bash "$REPO_ROOT/tests/test-rename-hook.sh"

run_test "tricycle generate settings registers UserPromptSubmit hook (tests/test-generate-settings-rename-hook.sh)" \
  bash "$REPO_ROOT/tests/test-generate-settings-rename-hook.sh"

run_test "kickoff commands carry Session Rename fallback (tests/test-command-rename-fallback.sh)" \
  bash "$REPO_ROOT/tests/test-command-rename-fallback.sh"

# ── Pull fresh base branch (TRI-32) ──

echo ""
echo "Pull fresh base branch (TRI-32):"

run_test "refresh_base_branch covers stale/fresh/dirty/offline/diverged/skip/nogit/chain-proxy (tests/test-refresh-base-branch.sh)" \
  bash "$REPO_ROOT/tests/test-refresh-base-branch.sh"

# ── Dogfood drift sync (TRI-33) ──

echo ""
echo "Dogfood drift sync (TRI-33):"

run_test "tricycle dogfood fixture behavior (tests/test-dogfood-cmd.sh)" \
  bash "$REPO_ROOT/tests/test-dogfood-cmd.sh"

run_test "core/ and mirrored .trc/.claude/ paths are in sync (tests/test-dogfood-drift.sh)" \
  bash "$REPO_ROOT/tests/test-dogfood-drift.sh"

# ── Graphify integration ──

echo ""
echo "Graphify integration:"

run_test "generate settings registers graphify hook (tests/test-generate-settings-graphify-hook.sh)" \
  bash "$REPO_ROOT/tests/test-generate-settings-graphify-hook.sh"
run_test "generate settings builds hooks and permissions only from config (tests/test-generate-settings-config-hooks.sh)" \
  bash "$REPO_ROOT/tests/test-generate-settings-config-hooks.sh"

run_test "style-gate lints persisted prose and fails open (tests/test-style-gate.sh)" \
  bash "$REPO_ROOT/tests/test-style-gate.sh"

run_test "generate settings turns style config into outputs (tests/test-generate-style.sh)" \
  bash "$REPO_ROOT/tests/test-generate-style.sh"

run_test "kickoff hook silent-skip gates (tests/test-graphify-hook-gating.sh)" \
  bash "$REPO_ROOT/tests/test-graphify-hook-gating.sh"

run_test "tricycle graphify subcommand lifecycle (tests/test-tricycle-graphify-cmd.sh)" \
  bash "$REPO_ROOT/tests/test-tricycle-graphify-cmd.sh"

run_test "graphify briefing contract (tests/test-graphify-briefing-contract.sh)" \
  bash "$REPO_ROOT/tests/test-graphify-briefing-contract.sh"

# ── Stealth mode (TRI-21) ──

echo ""
echo "Stealth mode (TRI-21):"

run_test "stealth keeps .claude committed, hides only internals (tests/test-stealth-keeps-claude-committed.sh)" \
  bash "$REPO_ROOT/tests/test-stealth-keeps-claude-committed.sh"

# ── Session-context injection cap (configurable) ──

echo ""
echo "Session-context cap:"

run_test "session-context max_chars is configurable, not a magic constant (tests/test-session-context-max-chars.sh)" \
  bash "$REPO_ROOT/tests/test-session-context-max-chars.sh"

# ── Summary ──

echo ""
echo "===================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
