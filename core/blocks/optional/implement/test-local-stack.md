---
name: test-local-stack
step: implement
description: Test implementation against local infrastructure stack
required: false
default_enabled: false
order: 45
---

## Local Stack Testing

**MANDATORY — NONNEGOTIABLE.** When this block is active, you MUST do all the steps below. Do not proceed to push-deploy before you do them. The push-deploy gate checks the evidence that step 4 writes.

**No exemptions that you give yourself.** Do not decide that your change is "exempt", "docs-only", "internal" or "without a runtime surface". Does a user get to the change, or can you see it at runtime? Then test it in a real browser against a running stack. Examples are an endpoint, a page, a feature flag, an auth flow or a background job. A spec that only says "X continues to work" is easy to test in a browser. It is not an exemption. The only skip is a skip that the user approves in this session. Ask the user. If they tell you to skip, write `USER-APPROVED SKIP: <reason>` as the first line of the marker (step 4).

Do this block after the implementation and before the QA testing gate.

### 0. Read the local testing notes

Read `qa/ai-agent-instructions.md` if it exists, and each local testing notes file that it names. These files record problems from earlier test sessions, for example the wrong database, old seed data or CORS.

### 1. Start the local stack

1. Start all the local services that the feature needs (databases, queues, caches, API servers). Use the start commands from the project notes. If there are no notes and Docker Compose is available, run `docker compose up -d`.
2. Start the web apps that the feature touches.
3. Make sure that each service is ready before you test. Use an HTTP probe, not a log search.

### 2. Test the feature in the browser

Use a browser MCP (Chrome DevTools MCP, or Playwright MCP if Chrome is not available):

1. Go to the related pages, in the sequence that a user uses.
2. Do the feature as a user does it: create, edit, delete and interact.
3. Make a screenshot at each important step.
4. Read the browser console and the network requests. Find errors, failed requests, CORS errors and uncaught exceptions.

Use data for a feature that shows data. A screenshot of an empty state is not a test.

### 3. Repair and test again

- If you find a problem (a visual bug, a console error, a CORS failure, an interaction that does not work), repair it before you continue.
- A CORS error is a real failure. Repair the allowed origins.
- After each repair, test again.

### 4. Write the evidence

The browser test is complete only when the evidence is on disk.

1. Save each screenshot from step 2 in `specs/<branch>/local-testing/`.
2. Write the marker. It must not be empty:

   ```bash
   mkdir -p specs/<branch>/local-testing
   cat > specs/<branch>/.local-testing-passed <<'MARKER'
   Local stack testing PASSED: <branch>
   Stack: <services and web app URLs>
   Flows tested in a real browser: <for example: register, login, vote>
   Screenshots: specs/<branch>/local-testing/*.png
   Console: no errors / <list>
   MARKER
   ```

The marker is valid only with a body and a minimum of one screenshot in `specs/<branch>/local-testing/`. A `USER-APPROVED SKIP:` first line is the only alternative. An empty marker, or a note that you wrote to give yourself an exemption, is not valid. Do not write the marker before you complete steps 1 to 3.

### 5. Record new problems

A step can fail because of an incorrect assumption, and then pass with different values. Examples are the wrong credentials, database, port or environment variable, or old data. Record each of these problems:

1. Read the local testing notes from step 0.
2. Find out if the notes already have the problem.
3. If not, add it to the notes, or to `qa/ai-agent-instructions.md` if there are no notes. Write:
   - **Problem**: what you thought, and what occurred
   - **Symptom**: the error or the unexpected behavior
   - **Repair**: what you did differently

### 6. Stop the web apps

When the test is complete, stop the web apps that you started. Keep the services running for the test suite in the next block.
