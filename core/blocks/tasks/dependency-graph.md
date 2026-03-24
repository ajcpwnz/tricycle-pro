---
name: dependency-graph
step: tasks
description: Generate dependency graph, parallel execution examples, and completion report
required: false
default_enabled: true
order: 40
---

5. **Report**: Output path to generated tasks.md and summary:
   - Total task count
   - Task count per user story
   - Parallel opportunities identified
   - Independent test criteria for each story
   - Suggested MVP scope (typically just User Story 1)
   - Format validation: Confirm ALL tasks follow the checklist format (checkbox, ID, labels, file paths)
