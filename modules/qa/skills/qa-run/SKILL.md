---
name: qa-run
description: Run QA test suites against the local dev stack using Chrome DevTools and Playwright MCPs. Verifies environment, executes test flows, monitors for network errors, writes results, and creates Linear tickets for failures.
disable-model-invocation: true
argument-hint: "[suite-name, 'all', or blank for auto-detect]"
---

## Input

```text
$ARGUMENTS
```

## Step 1: Read Operational Rules

Read `qa/ai-agent-instructions.md` in full. These rules override any assumptions. Pay special attention to:
- Environment setup (section 1)
- MCP priority: Chrome DevTools first, Playwright fallback (section 2)
- Test execution order (section 4)
- Test data setup (section 5)
- Auth state management (section 6)
- Results format (section 7)
- Playwright-specific notes (section 10)

## Step 2: Determine Which Suites to Run

Parse `$ARGUMENTS`:

- **Suite name** (e.g., `auth`, `polst`, `vote`, `social`, `campaign`, `brand`, `user`, `flag`, `studio`, `notif`, `settings`, `nav`, `cross`, `cattag`, `embed`, `metrics`, `og`, `anomaly`, `search`): Run only that suite from `qa/test-plan-ai-agent.md`.
- **`all`**: Run all 19 suites in the recommended execution order from the test plan.
- **Blank/empty**: Auto-detect from changed files. Run:
  ```bash
  git diff --name-only origin/staging
  ```
  Map changed files to suites using [suite-mapping.md](suite-mapping.md). Always include Suite 1 (AF-AUTH) as a prerequisite if any other suite needs it.

## Step 3: Verify Environment

Before running any tests, verify the dev stack is up:

1. **Docker**: `docker ps` — check `backend-postgres-1` and `backend-app-1` are running
2. **Backend**: `curl -s http://localhost:8000/health` or check docker logs for "running on port 8000"
3. **Frontend**: `curl -s http://localhost:3000` — should return HTML
4. **Manager**: `curl -s http://localhost:3001` — should return HTML
5. **Dashboard**: `curl -s http://localhost:3002` — should return HTML

If any service is down, start it:
```bash
cd apps/backend && docker compose up -d
bun run --filter @polst/frontend dev &
bun run --filter @polst/manager dev &
bun run --filter @polst/dashboard dev &
```

6. **Verify .env files** per the table in `qa/ai-agent-instructions.md` section 1. Fix if wrong.

## Step 4: Execute Test Cases

For each selected suite, execute test cases from `qa/test-plan-ai-agent.md`:

1. Follow the **dependency order** — run prerequisite flows first (e.g., AF-AUTH-003 before AF-AUTH-001)
2. Use **Chrome DevTools MCP** as the primary tool:
   - `browser_navigate` to load pages
   - `browser_snapshot` to inspect DOM
   - `browser_click`, `browser_fill_form` for interactions
   - `browser_take_screenshot` for visual evidence
   - `browser_console_messages` for error monitoring
3. Fall back to **Playwright MCP** only for:
   - Multi-step auth flows (register → login → navigate → interact)
   - File uploads
   - When Chrome DevTools is not available
4. **Monitor network errors** on EVERY page — check console for 4xx, 5xx, CORS errors, uncaught exceptions. Record ALL errors even if not in the test plan.
5. Take screenshots at key verification points.

## Step 5: Write Results

Create results at `qa/results-{date}/results.md` (use today's date in YYYY-MM-DD format).

Include:
- **Summary table**: Suite, Flow ID, Name, Result (PASS/FAIL/SKIP)
- **Detailed results** per flow with verification checklist items checked off
- **Network errors section** — ALL console errors observed, with endpoint, status code, error message
- **Screenshots index** — list of all screenshots taken with descriptions
- **Setup notes** — credentials used, test data created

## Step 6: Create Linear Tickets for Failures

For each FAIL result:
- Create **one Linear ticket per failure** (not batched)
- Team: **Polst**
- State: **Backlog**
- Labels: `claude-ticket`, `needs-review`
- Include: reproduction steps, expected vs actual, screenshot, test case ID
- Only create tickets if the user asks for it or if instructed in `$ARGUMENTS`
