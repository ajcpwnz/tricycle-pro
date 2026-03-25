---
name: agent-context
step: plan
description: Update AI agent context files with plan information
required: false
default_enabled: true
order: 60
---

3. **Agent context update**:
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
   - These scripts detect which AI agent is in use
   - Update the appropriate agent-specific context file
   - Add only new technology from current plan
   - Preserve manual additions between markers
