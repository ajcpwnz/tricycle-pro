# Quickstart: QA Testing Block

## For users

### Enable QA in your project

1. Set `qa.enabled: true` in `tricycle.config.yml`:
   ```yaml
   qa:
     enabled: true
   ```

2. Run `tricycle assemble` to rebuild commands.

3. (Optional) Create `qa/ai-agent-instructions.md` with testing prerequisites and setup guidance.

4. Run `/trc.implement` — the agent will now run all `apps[].test` commands and halt before push if anything fails.

### Add testing instructions

Create `qa/ai-agent-instructions.md` in your project root:

```markdown
# QA Testing Instructions

## Prerequisites
- Start Docker: `cd apps/backend && docker compose up -d`
- Start frontend: `bun run --filter @myapp/frontend dev`

## Environment
- Backend runs on port 8000
- Frontend runs on port 3000

## Operational Rules
- Use Chrome DevTools MCP for visual verification
- Check browser console for errors after each test
```

The agent reads this file before running tests and appends learnings to it over time.

## For developers (implementing this feature)

### Files to create/modify

1. **Create** `core/blocks/optional/implement/qa-testing.md` — the block template
2. **Modify** `core/scripts/bash/assemble-commands.sh` — add feature flag auto-enable logic
3. **Modify** `core/scripts/bash/common.sh` — add `cfg_get_bool` helper if needed
4. **Create** test cases in `tests/` for assembly with qa enabled/disabled

### Test locally

```bash
# Enable qa in tricycle.config.yml, then:
bash bin/tricycle assemble --dry-run
# Verify trc.implement.md includes QA testing section

# Disable qa, re-assemble:
bash bin/tricycle assemble --dry-run
# Verify trc.implement.md does NOT include QA testing section
```
