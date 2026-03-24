#!/bin/bash
# PostToolUse hook: reminds Claude to run lint/test after trc.implement finishes

INPUT=$(cat)

# Only act on trc.implement skill
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
if [ "$SKILL" != "trc.implement" ]; then
  exit 0
fi

# Build command list from tricycle.config.yml if available
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
CONFIG="$REPO_ROOT/tricycle.config.yml"
COMMANDS=""

if [ -f "$CONFIG" ] && command -v node >/dev/null 2>&1; then
  COMMANDS=$(node -e "
    const fs = require('fs');
    const yaml = require('$REPO_ROOT/node_modules/yaml');
    const config = yaml.parse(fs.readFileSync('$CONFIG', 'utf-8'));
    const lines = [];
    for (const app of (config.apps || [])) {
      const cd = app.path && app.path !== '.' ? 'cd ' + app.path + ' && ' : '';
      if (app.lint) lines.push('- ' + app.name + ': ' + cd + app.lint);
      if (app.test) lines.push('- ' + app.name + ': ' + cd + app.test);
    }
    console.log(lines.join('\\\\n'));
  " 2>/dev/null)
fi

if [ -z "$COMMANDS" ]; then
  COMMANDS="- Run your project's lint and test commands for all affected apps"
fi

cat <<EOJSON
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"MANDATORY POST-IMPLEMENT GATE: Implementation is complete. You MUST now run lint and test for ALL affected apps before declaring work done. Run these commands:\n${COMMANDS}\nFix any failures. Do NOT skip this step or tell the user work is done until all checks pass."}}
EOJSON
