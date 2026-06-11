#!/usr/bin/env bash
# Contract test for the recon template used by /trc.band.
# Guards the section set the orchestrator and its workers rely on: the
# roadmap drives wave scheduling, the checklist drives run accounting.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/core/templates/recon-template.md"

fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$TEMPLATE" ] || fail "recon template missing: $TEMPLATE"

# Mandatory top-level sections.
for heading in \
    "## Epic Overview" \
    "## Sub-Issues" \
    "## Codebase Recon" \
    "## Dependency Roadmap" \
    "## Verification Strategy" \
    "## Integration Plan" \
    "## Risks & Open Questions" \
    "## Epic Checklist"
do
    grep -qF "$heading" "$TEMPLATE" || fail "missing section: $heading"
done

# Roadmap subsections that band-run.sh init consumes (waves, deps, models).
for sub in "### Dependency Graph" "### Waves" "### Complexity & Model Assignment"; do
    grep -qF "$sub" "$TEMPLATE" || fail "missing roadmap subsection: $sub"
done

# Mandatory markers on load-bearing sections.
count=$(grep -c '\*(mandatory)\*' "$TEMPLATE")
[ "$count" -ge 6 ] || fail "expected >= 6 *(mandatory)* markers, found $count"

# Checklist is orchestrator-owned and must say so.
grep -qi 'orchestrator only' "$TEMPLATE" || fail "checklist must state it is orchestrator-ticked only"

# Recon gate: template status reflects the approval pause.
grep -qi 'awaiting user approval' "$TEMPLATE" || fail "template must carry the awaiting-approval status"

# Clarification markers must be documented as pausing the band.
grep -qF 'NEEDS CLARIFICATION' "$TEMPLATE" || fail "missing NEEDS CLARIFICATION convention"

echo "recon-template contract: OK"
