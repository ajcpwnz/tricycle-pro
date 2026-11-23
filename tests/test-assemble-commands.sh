#!/usr/bin/env bash
# The assembler builds exactly trc.plan.md and trc.implement.md from blocks:
# defaults, feature flags, enable/disable (required blocks cannot be disabled),
# optional blocks and custom blocks, in `order`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASM="$REPO_ROOT/core/scripts/bash/assemble-commands.sh"
BLOCKS="$REPO_ROOT/core/blocks"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

assemble() { # <config file> <out dir>
  bash "$ASM" --blocks-dir="$BLOCKS" --output-dir="$2" --config="$1" >/dev/null
}
headings() { grep '^## ' "$1" | tr '\n' '|'; }

# Defaults: no config at all.
assemble "$TMP/none.yml" "$TMP/default"
[ "$(ls "$TMP/default" | tr '\n' ' ')" = "trc.implement.md trc.plan.md " ] \
  || fail "assembler must write exactly trc.plan.md and trc.implement.md, got: $(ls "$TMP/default")"
[ "$(headings "$TMP/default/trc.plan.md")" = "## User Input|## Resolve the input|## Plan mode|## Graphify Context|## Research|## Write the spec|## Validation|## Store|" ] \
  || fail "default plan sections: $(headings "$TMP/default/trc.plan.md")"
[ "$(headings "$TMP/default/trc.implement.md")" = "## User Input|## Load the spec|## Validation gate|## Graphify Context|## Work the checklist|## Lint and test|## Version bump|## Push, PR & Deploy|" ] \
  || fail "default implement sections: $(headings "$TMP/default/trc.implement.md")"
grep -q '^description: ' "$TMP/default/trc.plan.md" || fail "plan has no description frontmatter"
grep -q 'trc-spec-validator' "$TMP/default/trc.plan.md" || fail "plan does not run the validator"
grep -q 'trc-spec-validator' "$TMP/default/trc.implement.md" || fail "implement does not run the validator"
grep -qx 'model: fable' "$TMP/default/trc.plan.md" || fail "plan default model is not fable"
grep -qx 'model: opus' "$TMP/default/trc.implement.md" || fail "implement default model is not opus"
grep -q 'model `opus`' "$TMP/default/trc.implement.md" || fail "worker/validator default model is not opus"
! grep -q '{{' "$TMP/default/trc.plan.md" "$TMP/default/trc.implement.md" || fail "placeholder left in output"

# Flags, enable/disable, optional and custom blocks.
mkdir -p "$TMP/custom"
cat > "$TMP/custom/house-rules.md" <<'EOF'
---
name: house-rules
step: implement
description: test custom block
required: false
default_enabled: true
order: 35
---

## House Rules
EOF
cat > "$TMP/cfg.yml" <<EOF
models:
  plan: opus
  implement: sonnet
  workers: haiku   # cheap workers
  validator: fable
worktree:
  enabled: true
qa:
  enabled: true
workflow:
  blocks:
    plan:
      disable:
        - plan-mode
        - validate
      enable:
        - catholic
    implement:
      custom:
        - $TMP/custom/house-rules.md
EOF
assemble "$TMP/cfg.yml" "$TMP/cfg"
P=$(headings "$TMP/cfg/trc.plan.md"); I=$(headings "$TMP/cfg/trc.implement.md")
case "$P" in *"## Plan mode"*) fail "disabled optional-by-default block still present: $P" ;; esac
case "$P" in *"## Validation"*) ;; *) fail "required block was disabled: $P" ;; esac
case "$P" in "## User Input|## Invocation of Divine Guidance|"*) ;; *) fail "enabled optional block missing or misordered: $P" ;; esac
[ "$I" = "## User Input|## Load the spec|## Validation gate|## Worktree|## Graphify Context|## Work the checklist|## House Rules|## Lint and test|## QA Testing Gate|## Version bump|## Push, PR & Deploy|## Worktree Cleanup|" ] \
  || fail "implement with flags and custom block: $I"

grep -qx 'model: opus' "$TMP/cfg/trc.plan.md" || fail "models.plan override ignored"
grep -qx 'model: sonnet' "$TMP/cfg/trc.implement.md" || fail "models.implement override ignored"
grep -q 'model `haiku`' "$TMP/cfg/trc.implement.md" || fail "models.workers override ignored"
grep -q 'model `fable`' "$TMP/cfg/trc.implement.md" || fail "models.validator override ignored"

# A missing custom block is an error, not a silent skip.
printf 'workflow:\n  blocks:\n    plan:\n      custom:\n        - %s/nope.md\n' "$TMP" > "$TMP/bad.yml"
if bash "$ASM" --blocks-dir="$BLOCKS" --output-dir="$TMP/bad" --config="$TMP/bad.yml" >/dev/null 2>&1; then
  fail "missing custom block did not fail assembly"
fi

echo "assemble-commands: OK"
