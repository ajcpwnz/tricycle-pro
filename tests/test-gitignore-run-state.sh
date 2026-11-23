#!/usr/bin/env bash
# `tricycle generate gitignore` ignores chain and band run state, adds the rules
# to an older .gitignore once, keeps specs/ itself committable, and adds the
# .claude/agents/ rule to an older .claude block.
set -euo pipefail
CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/tricycle"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q
printf 'project:\n  name: f\n  type: single-app\n' > tricycle.config.yml
printf '.claude/*\n!.claude/settings.json\n' > .gitignore
"$CLI" generate gitignore >/dev/null; "$CLI" generate gitignore >/dev/null
for r in 'specs/.chain-runs/' 'specs/.band-runs/'; do
  [ "$(grep -cxF "$r" .gitignore)" = 1 ] || { echo "FAIL: $r not present exactly once"; exit 1; }
done
git check-ignore -q specs/.band-runs/r1/state.json || { echo "FAIL: band run state not ignored"; exit 1; }
git check-ignore -q specs/.chain-runs/r1/state.json || { echo "FAIL: chain run state not ignored"; exit 1; }
[ "$(grep -cx '!\.claude/agents/' .gitignore)" = 1 ] || { echo "FAIL: older block did not get exactly one !.claude/agents/ rule"; exit 1; }
! git check-ignore -q .claude/agents/trc-spec-validator.md || { echo "FAIL: .claude/agents/ is ignored"; exit 1; }
! git check-ignore -q specs/TRI-1/.local-testing-passed || { echo "FAIL: specs/<branch> is ignored"; exit 1; }
echo "gitignore-run-state: OK"
