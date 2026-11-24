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
[ "$(headings "$TMP/default/trc.plan.md")" = "## User Input|## Store setup|## Resolve the input|## Plan mode|## Graphify Context|## Research|## Write the spec|## Validation|## Store|" ] \
  || fail "default plan sections: $(headings "$TMP/default/trc.plan.md")"
[ "$(headings "$TMP/default/trc.implement.md")" = "## User Input|## Store setup|## Load the spec|## Validation gate|## Graphify Context|## Work the checklist|## Lint and test|## Version bump|## Push, PR & Deploy|" ] \
  || fail "default implement sections: $(headings "$TMP/default/trc.implement.md")"
grep -q '^description: ' "$TMP/default/trc.plan.md" || fail "plan has no description frontmatter"
grep -q 'trc-spec-validator' "$TMP/default/trc.plan.md" || fail "plan does not run the validator"
grep -q 'trc-spec-validator' "$TMP/default/trc.implement.md" || fail "implement does not run the validator"
grep -qx 'model: fable' "$TMP/default/trc.plan.md" || fail "plan default model is not fable"
grep -qx 'model: opus' "$TMP/default/trc.implement.md" || fail "implement default model is not opus"
grep -q 'model `opus`' "$TMP/default/trc.implement.md" || fail "worker/validator default model is not opus"
! grep -q '{{' "$TMP/default/trc.plan.md" "$TMP/default/trc.implement.md" || fail "placeholder left in output"

# Validation: only blockers (gaps that break the app or the feature) fail a
# spec. Plan fixes blockers and revalidates; handoffs go to the implementer.
# The implement gate skips the validator when no cited file changed.
P="$TMP/default/trc.plan.md"; I="$TMP/default/trc.implement.md"
grep -q 'run the validator again on the full spec' "$P" || fail "plan does not revalidate after fixing blockers"
grep -q 'After three rounds' "$P" || fail "plan revalidation has no round limit"
grep -q 'Do not fix handoffs here' "$P" || fail "plan fixes handoffs"
grep -q 'Implementer Notes' "$P" || fail "plan does not hand off to the implementer"
grep -q 'spec-rubric.md' "$P" || fail "plan writer does not read the rubric"
grep -q 'Status: validated @ <sha>' "$P" || fail "plan does not record the validated commit"
grep -q 'git diff --name-only <sha>' "$I" || fail "implement gate does not skip an unchanged spec"
grep -q 'Implementer Notes' "$I" || fail "implement does not resolve implementer notes"
cmp -s "$P" "$REPO_ROOT/core/commands/trc.plan.md" || fail "core/commands/trc.plan.md differs from the assembled default"
cmp -s "$I" "$REPO_ROOT/core/commands/trc.implement.md" || fail "core/commands/trc.implement.md differs from the assembled default"

# Obsidian store: a one-time setup step asks fixed questions, and the store,
# load, checklist and cleanup sections read and patch the note in the vault.
section() { awk -v h="## $2" '$0 == h { f = 1; print; next } /^## / { f = 0 } f' "$1"; }
body() { awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } !fm' "$1"; }
[ "$(body "$BLOCKS/plan/setup-store.md")" = "$(body "$BLOCKS/implement/setup-store.md")" ] \
  || fail "plan and implement setup-store bodies differ"
for F in "$P" "$I"; do
  S=$(section "$F" "Store setup")
  for k in spec.dir spec.obsidian.note_name spec.obsidian.frontmatter spec.obsidian.done AskUserQuestion; do
    grep -qF "$k" <<<"$S" || fail "$(basename "$F") setup does not name $k"
  done
  grep -qF 'an `obsidian` MCP server is connected and the config has no `spec.store` key' <<<"$S" \
    || fail "$(basename "$F") setup has no store question trigger"
  grep -qF 'Do not ask a question again when its key is already in `tricycle.config.yml`' <<<"$S" \
    || fail "$(basename "$F") setup has no ask-once rule"
  grep -qF '/trc.chain' <<<"$S" || fail "$(basename "$F") setup does not stop unattended runs"
  grep -qF 'tricycle generate mcp' "$F" && grep -qF 'OBSIDIAN_VAULT_PATH' "$F" \
    && grep -qF 'Do not fall back to a repo file' "$F" || fail "$(basename "$F") has no stop rule for a missing obsidian server"
done
section "$P" "Resolve the input" | grep -qF 'a spec id with a note in `<spec.dir>` in the vault' || fail "plan resolve-input ignores existing vault notes"
S=$(section "$P" "Store")
grep -qF 'spec.store: obsidian' <<<"$S" && grep -qF 'spec.obsidian.note_name' <<<"$S" \
  && grep -qF 'spec.obsidian.frontmatter' <<<"$S" && grep -qF 'vault-relative path' <<<"$S" \
  || fail "plan store section has no obsidian text"
section "$P" "Validation" | grep -qF 'patch tool of the `obsidian` server' || fail "plan validation does not patch the note"
section "$I" "Load the spec" | grep -qF 'spec.obsidian.note_name' || fail "implement load does not read the note"
S=$(section "$I" "Validation gate")
grep -qF 'does not see changes to the note' <<<"$S" && grep -qF 'patch tool of the `obsidian` server' <<<"$S" \
  || fail "implement gate has no obsidian text"
section "$I" "Work the checklist" | grep -qF 'the note in obsidian mode' || fail "implement checklist does not mark the note"
S=$(section "$I" "Push, PR & Deploy")
grep -qF 'stays in the vault' <<<"$S" && grep -qF 'spec.obsidian.done: move' <<<"$S" && grep -qF '<spec.dir>/done' <<<"$S" \
  || fail "implement cleanup has no obsidian text"

V="$REPO_ROOT/core/agents/trc-spec-validator.md"; R="$REPO_ROOT/core/templates/spec-rubric.md"
T="$REPO_ROOT/core/templates/spec-template.md"
[ -f "$R" ] || fail "core/templates/spec-rubric.md is missing"
grep -q '^## Blocker' "$R" && grep -q '^## Handoff' "$R" && grep -q '^## Writer checks' "$R" || fail "rubric has no Blocker, Handoff or Writer checks section"
grep -q 'breaks the app or the feature' "$R" || fail "rubric blocks on more than breaking gaps"
grep -q '^## Implementer Notes' "$T" || fail "spec template has no Implementer Notes section"
grep -q 'spec-rubric.md' "$V" || fail "validator does not read the rubric"
grep -q '^## Output' "$V" || fail "validator has no Output section"
grep -q 'PASS when there is no blocker' "$V" || fail "validator fails on handoffs"
grep -q '^HANDOFFS:' "$V" || fail "validator output has no handoffs"
! grep -q 'You get one round\|\[blocking|note\]' "$V" || fail "validator keeps the old one-round rules"

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
[ "$I" = "## User Input|## Store setup|## Load the spec|## Validation gate|## Worktree|## Graphify Context|## Work the checklist|## House Rules|## Lint and test|## QA Testing Gate|## Version bump|## Push, PR & Deploy|## Worktree Cleanup|" ] \
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
