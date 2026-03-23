---
name: Never push without explicit user approval
description: Always wait for user to say "push" or "go ahead" before pushing code or creating PRs
type: feedback
---

NEVER push code or create PRs without explicit user approval. Each push requires fresh
confirmation — prior approval does not carry over to new pushes.

**Why:** Unauthorized pushes can trigger deploys, CI pipelines, or notifications that the user
isn't ready for. The cost of asking is near-zero; the cost of an unwanted push can be high.

**How to apply:** When work is complete (lint/test pass), summarize the changes and state you
are ready to push. Wait for the user to explicitly say "push", "go ahead", or equivalent.
