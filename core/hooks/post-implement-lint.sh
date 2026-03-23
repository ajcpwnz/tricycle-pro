#!/bin/bash
# PostToolUse hook: reminds Claude to run lint/test after trc.implement finishes

INPUT=$(cat)

# Only act on trc.implement skill
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
if [ "$SKILL" != "trc.implement" ]; then
  exit 0
fi

cat <<EOJSON
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"MANDATORY POST-IMPLEMENT GATE: Implementation is complete. You MUST now run lint and test for ALL affected apps before declaring work done. Run these commands:\n- Backend: cd apps/backend && bun run lint && bun run test\n- Frontend: cd apps/frontend && bun run lint\n- Manager: cd apps/manager && bun run lint\nFix any failures. Do NOT skip this step or tell the user work is done until all checks pass."}}
EOJSON
