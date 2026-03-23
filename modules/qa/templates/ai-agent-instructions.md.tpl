# QA Agent Instructions

## Environment: Local Dev Stack Only

Always test against the local dev stack. Start all services before testing.

<!-- Customize this section with your project's specific dev commands and ports -->

### MCP Priority
Use **Chrome DevTools MCP** as the primary testing tool.
Use **Playwright MCP** only as a fallback when Chrome cannot achieve the test
(e.g., multi-step auth flows, file uploads, headless automation).

## What to Test
- Execute test cases from `qa/test-plan-ai-agent.md` in dependency order.
- **MANDATORY**: Monitor for network errors — check browser console for failed requests
  (4xx, 5xx), CORS errors, and uncaught exceptions. Record ALL errors.

## Test Data Setup
- Database starts empty — all test data is created during the test run.
- Create test accounts via the app's registration flow.
- Admin accounts may need seeding via CLI scripts.

## Writing Results
Write all results to `qa/results-<date>/results.md` with screenshots in the same directory.

Include:
- Summary table (pass/fail per suite)
- Detailed results per test flow with checklist
- Network errors section
- Screenshots index

## Linear Tickets (if configured)
- Create ONE ticket per issue (not batched)
- Attach screenshots when applicable
- Include reproduction steps, expected vs actual, severity
