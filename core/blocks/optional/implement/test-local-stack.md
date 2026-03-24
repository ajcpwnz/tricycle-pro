---
name: test-local-stack
step: implement
description: Test implementation against local infrastructure stack
required: false
default_enabled: false
order: 45
---

## Local Stack Testing

Before marking implementation as complete, verify the implementation works against the local development stack:

1. **Ensure local services are running**: Check that all required local services (databases, message queues, caches, API servers) are running. If Docker Compose is available, run `docker compose up -d` to start dependencies.

2. **Run integration tests against local stack**: Execute any integration tests that target local services rather than mocks. Verify actual data flows through the system.

3. **Manual smoke test**: Perform a manual walkthrough of the primary user journey against the local stack to verify end-to-end behavior.

4. **Check logs and monitoring**: Review application logs for errors, warnings, or unexpected behavior during testing.

If local stack testing reveals issues, fix them before proceeding to completion validation.
