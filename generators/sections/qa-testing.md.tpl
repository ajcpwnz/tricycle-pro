## QA Testing (MANDATORY — NONNEGOTIABLE)

When asked to run QA tests, follow these rules strictly.

### MCP Priority
Use **{{qa.primary_tool}}** as the PRIMARY testing tool. Use **{{qa.fallback_tool}}**
only as a fallback when the primary tool cannot achieve the test.

### What to Test
- Execute test cases from the QA test plan.
- Monitor for network errors: check browser console for failed requests, 500s, CORS errors,
  and uncaught exceptions. Record ALL of them.

### Results
Write all results to `{{qa.results_dir}}/results.md` with screenshots in the same directory.
