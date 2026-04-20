---
description: Create or update the feature specification from a natural language feature description.
handoffs:
  - label: Build Technical Plan
    agent: trc.plan
    prompt: Create a plan for the spec. I am building with...
  - label: Clarify Spec Requirements
    agent: trc.clarify
    prompt: Clarify specification requirements
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).


## Session Rename (Fallback)

**Primary mechanism**: the `UserPromptSubmit` hook at
`.claude/hooks/rename-on-kickoff.sh` has already renamed the session by the
time you see this prompt — in that case this block is a silent no-op.

This block exists only as a fallback for installs where the hook is not
registered (older `tricycle init` that predates TRI-31 and hasn't run
`tricycle update` + `tricycle generate settings`) or hosts that do not honor
`hookSpecificOutput.sessionTitle`.

**First thing done — before any file, git, or Linear side effect:**

1. Derive the target session label by invoking the shared helper:
   ```bash
   .trc/scripts/bash/derive-branch-name.sh \
     --style "<configured-style>" \
     [--prefix "<configured-prefix>"] [--issue "<ticket-id-if-known>"] \
     "$ARGUMENTS"
   ```
   (Do NOT pass `--short-name` — the helper's auto-derived slug is the
   label the hook uses, and this fallback must produce the same label for
   idempotency.)
2. Read the current session label from `$CLAUDE_SESSION_TITLE` if
   available.
3. If the current label differs from the derived target, emit
   `/rename <target>` as the first text in your turn, before any tool
   call. If the current label matches (or if `$CLAUDE_SESSION_TITLE` is
   unset and you cannot tell), skip silently.
4. If the configured style is `issue-number` and the description contains
   no ticket ID yet, defer this block until Step 2 has asked the user for
   the ID, then come back and rename before running `create-new-feature.sh`.

This step must complete (or be deferred per rule 4) before the
"Worktree Setup (Detection)" block below.


## Graphify Context

**Runtime gate — evaluate before acting on this block.** This block is
active for this turn if AND ONLY IF both conditions hold:

1. `tricycle.config.yml` has `integrations.graphify.enabled: true`.
2. `graphify-out/graph.json` exists at the repo root.

If either check fails, skip this entire section — it does not apply and
you MUST NOT attempt any graphify call. Continue with normal
grep/read/file-based exploration.

If both checks pass, a knowledge graph of this repo is available to
short-circuit the usual 'open files to find things' loop. Prefer
querying it BEFORE wide file reads:

- **GRAPH REPORT** (read once for orientation):
  `graphify-out/GRAPH_REPORT.md` — lists god nodes, surprising
  connections, and suggested questions.
- **LOCAL QUERY** (cheap, no MCP needed):
  - `graphify query "<your question>"` — BFS traversal for a question.
  - `graphify explain "<symbol-or-concept>"` — plain-language expansion
    of a node and its neighbors.
  - `graphify path "<A>" "<B>"` — shortest path between two concepts.
- **RAW JSON**: `graphify-out/graph.json` when you need every edge.
- **MCP** (only if `.mcp.json` has a `graphify` entry AND it was
  registered before this `claude` session started): tools
  `{query_graph, get_node, get_neighbors, get_community, god_nodes,
  graph_stats, shortest_path}`. Mid-session `.mcp.json` edits do NOT
  hot-load, so do not assume these tools exist — probe by calling one
  and fall back to the shell CLI above on failure.

**WHEN to query**: architectural questions (where is X defined, who
calls Y, what depends on Z), code-location lookups before grepping,
"is there already a util for this?". Every edge carries a provenance
tag — EXTRACTED (found directly), INFERRED (reasonable guess with
confidence), AMBIGUOUS (flagged). Treat INFERRED as a hint, not truth.

**WHEN NOT to query**: trivial one-file edits, cosmetic fixes, anything
where you already know the exact file path. The graph is a shortcut,
not a mandatory gate.

**STALENESS**: the graph is refreshed automatically by the kickoff
hook before you started. If you touch code and then need to re-query
the updated state, run `graphify . --update` yourself — do NOT trust
stale nodes after you've mutated the tree.

## Worktree Setup (Detection)

Before creating the feature branch, determine whether you need to work in a git worktree.

### Pre-provisioned worktree (orchestrator handoff)

If the environment variable `TRC_PREPROVISIONED_WORKTREE` is set to a path, or
your current working directory already is an initialized feature worktree
(i.e. `.git` is a file AND `HEAD` points to a non-default branch that already
exists), the worktree has been provisioned by an orchestrator (typically
`/trc.chain`). In that case:

- Set `WORKTREE_MODE=preprovisioned`.
- Set `BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)` — do **not** derive it
  from the feature description, and do **not** append a suffix.
- Set `SPEC_FILE=specs/$BRANCH_NAME/spec.md` — the spec directory name MUST
  equal the branch name exactly (the pre-push marker hook on the consumer side
  expects `specs/<BRANCH_NAME>/.local-testing-passed`, so any suffix like
  `-procedures` will break the push).
- SKIP Step 2 (`create-new-feature.sh`) entirely. The branch already exists;
  re-running the script will fail with "branch already exists" or create a
  stale duplicate.
- SKIP Step 2b (worktree creation). You are already in the worktree.
- Proceed directly to Step 3 (Load template) using the existing
  `$SPEC_FILE`, creating the spec directory + copying the template if the
  file doesn't exist yet:
  ```bash
  mkdir -p "specs/$BRANCH_NAME"
  [ -f "$SPEC_FILE" ] || cp .trc/templates/spec-template.md "$SPEC_FILE"
  ```

### Detection (normal flow)

If the pre-provisioned case above does not apply, check the current working directory:
- If `.git` is a **file** (not a directory), you are already in a worktree. Set `WORKTREE_MODE=already` and proceed to the next block.
- If `.git` is a **directory**, you are in the main checkout. Set `WORKTREE_MODE=needed` — the feature-setup block will handle worktree creation after branch creation.

### Configuration

Read `tricycle.config.yml` for worktree settings:
- `project.name` — for substitution into the path pattern
- Default worktree path: `../{project}-{branch}` (where `{project}` is the project name and `{branch}` is the branch name from the script output)

Keep these values available for the feature-setup block.

### Notes

- This block only detects and configures. It does NOT create branches or worktrees.
- The feature-setup block (next) will use `WORKTREE_MODE` to decide whether to pass `--no-checkout` to `create-new-feature.sh` and whether to create the worktree after branch creation.
- The worktree isolates feature work from the main checkout, preventing accidental changes to main.
- If worktree creation fails later (e.g., branch already checked out elsewhere), report the error and suggest the user resolve the conflict manually.


## Outline

The text the user typed after `/trc.specify` in the triggering message **is** the feature description. Assume you always have it available in this conversation even if `$ARGUMENTS` appears literally below. Do not ask the user to repeat it unless they provided an empty command.

Given that feature description, do this:

### Step 0: Read branch naming configuration

Read `tricycle.config.yml` in the project root and check for:
- `branching.style` — one of `feature-name` (default), `issue-number`, or `ordered`
- `branching.prefix` — issue prefix for `issue-number` style (e.g., `TRI`, `JIRA`)

If `branching` section is missing, use `feature-name` as the default style.

### Step 1: Generate a concise short name (2-4 words) for the branch

- Analyze the feature description and extract the most meaningful keywords
- Create a 2-4 word short name that captures the essence of the feature
- Use action-noun format when possible (e.g., "add-user-auth", "fix-payment-bug")
- Preserve technical terms and acronyms (OAuth2, API, JWT, etc.)
- Keep it concise but descriptive enough to understand the feature at a glance
- Examples:
  - "I want to add user authentication" → "user-auth"
  - "Implement OAuth2 integration for the API" → "oauth2-api-integration"
  - "Create a dashboard for analytics" → "analytics-dashboard"
  - "Fix payment processing timeout bug" → "fix-payment-timeout"

### Step 2: Create the feature branch (style-aware)

Build the script invocation based on the configured `branching.style`:

**For `feature-name` style** (default):
```bash
.trc/scripts/bash/create-new-feature.sh "$ARGUMENTS" --json --style feature-name --short-name "<slug>"
```
No numeric prefix. Branch name will be the slug directly (e.g., `dark-mode-toggle`).

**For `issue-number` style**:
1. Scan the user's description for an issue identifier matching the configured `branching.prefix` pattern (e.g., `TRI-042`). If no prefix is configured, look for any `LETTERS-DIGITS` pattern.
2. If an issue number is found:
   ```bash
   .trc/scripts/bash/create-new-feature.sh "$ARGUMENTS" --json --style issue-number --issue "<ISSUE_ID>" --prefix "<PREFIX>" --short-name "<slug>"
   ```
3. If **no issue number is found** in the description:
   - Ask the user: "What is the issue number? (e.g., `<PREFIX>-042`)"
   - Wait for the user's response
   - Then run the script with `--issue <user_response>`

   Branch name will be `<ISSUE>-<slug>` (e.g., `TRI-042-export-csv`).

**For `ordered` style**:
```bash
.trc/scripts/bash/create-new-feature.sh "$ARGUMENTS" --json --style ordered --short-name "<slug>"
```
The script auto-detects the next sequential number. Branch name will be `###-<slug>` (e.g., `004-notifications`).

**IMPORTANT**:
- Always include `--json` so the output can be parsed reliably
- You must only ever run this script once per feature
- The JSON output will contain BRANCH_NAME and SPEC_FILE paths
- For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot")

### Step 2b: Worktree creation (if worktree-setup block is active)

If `WORKTREE_MODE=needed` (set by the worktree-setup block above):

1. **Add `--no-checkout` to the script invocation from Step 2.** This creates the branch without switching to it and without creating the spec directory or template file. The JSON output still contains BRANCH_NAME, SPEC_FILE, and FEATURE_NUM.

2. **After parsing the JSON output**, create the worktree using the branch name:
   ```bash
   git worktree add ../{project}-{BRANCH_NAME} {BRANCH_NAME}
   ```
   Where `{project}` is `project.name` from `tricycle.config.yml`.

3. **Copy `.trc/`** from the main checkout to the worktree if it does not exist (it is typically gitignored):
   ```bash
   cp -r /path/to/main/.trc /path/to/worktree/.trc
   ```

4. **Change your working context to the worktree directory.** All subsequent operations MUST happen in the worktree.

5. **Create the spec directory and copy the template** inside the worktree:
   ```bash
   mkdir -p specs/{BRANCH_NAME}
   cp .trc/templates/spec-template.md specs/{BRANCH_NAME}/spec.md
   ```

If `WORKTREE_MODE` is not set (worktree-setup block is not active), skip this step — the script already handled checkout, spec directory, and template in Step 2.

### Step 3: Load template

Load `.trc/templates/spec-template.md` to understand required sections.

**NOTE:**
- Without worktree mode: The script creates and checks out the new branch and initializes the spec file.
- With worktree mode (`--no-checkout`): The script only creates the branch and outputs JSON. The spec directory, template copy, and worktree are set up in Step 2b.


## Chain Validation

Before proceeding, read `tricycle.config.yml` and check the `workflow.chain` configuration.

1. If `workflow.chain` is not defined, use the default chain: `[specify, plan, tasks, implement]`.
2. Validate the chain is one of these valid configurations:
   - `[specify, plan, tasks, implement]` (default — full workflow)
   - `[specify, plan, implement]` (tasks absorbed into plan)
   - `[specify, implement]` (plan and tasks absorbed into specify)
3. If the chain is invalid, STOP and output:
   ```
   Error: Invalid workflow chain configuration.
   Valid chains: [specify, plan, tasks, implement], [specify, plan, implement], [specify, implement]
   ```
4. Verify that `specify` is present in the configured chain. If not, STOP and output:
   ```
   Error: Step 'specify' is not part of the configured workflow chain.
   ```

Note the chain configuration — it will be used by subsequent blocks to determine absorbed responsibilities.


## Input Detail Validation

After reading the chain configuration, validate that the user's feature description provides sufficient detail for the configured chain length. Shorter chains require more detailed input because fewer planning phases are available to flesh out the details.

### Validation Rules by Chain Length

**Full chain `[specify, plan, tasks, implement]`**:
- Accept any non-empty feature description.
- Planning and task generation phases will flesh out the details.
- No minimum detail requirement beyond a basic description.

**Three-step chain `[specify, plan, implement]`**:
- The feature description should describe at least:
  - **Scope**: What the feature does and doesn't include
  - **Expected outcomes**: What success looks like
- If the description is very brief (roughly 1-2 sentences with no specifics), output:
  ```
  Your feature description may be too brief for a shortened workflow chain.
  Since the tasks step is omitted, the plan step will also generate tasks.
  Consider adding: scope boundaries and expected outcomes.
  ```
  Then ask the user if they want to proceed or provide more detail.

**Two-step chain `[specify, implement]`**:
- The feature description MUST describe at least:
  - **Scope**: What the feature does and its boundaries
  - **Expected behavior**: How it should work from a user perspective
  - **Technical constraints**: Key limitations or requirements
  - **Acceptance criteria**: How to verify the feature works
- If the description lacks these elements (roughly under 3-4 sentences with no technical detail), STOP and output:
  ```
  Error: Feature description is too brief for a specify-implement chain.

  Since plan and tasks steps are omitted, the specify step must also handle
  technical planning and task generation. Please provide more detail:

  - Scope: What does this feature include/exclude?
  - Expected behavior: How should it work?
  - Technical constraints: Any limitations or requirements?
  - Acceptance criteria: How do we verify it works?

  Provide an expanded description or switch to a longer chain in tricycle.config.yml.
  ```
  Wait for the user to provide a more detailed description before proceeding.

### Notes

- This validation uses AI judgment, not rigid character counts. A concise but information-dense description may pass even if short.
- If the user has provided enough semantic content (clear scope, outcomes, constraints) the description should be accepted regardless of length.
- A highly detailed prompt always passes regardless of chain length.


## Execution Flow

1. Parse user description from Input
   If empty: ERROR "No feature description provided"
2. Extract key concepts from description
   Identify: actors, actions, data, constraints
3. For unclear aspects:
   - Make informed guesses based on context and industry standards
   - Only mark with [NEEDS CLARIFICATION: specific question] if:
     - The choice significantly impacts feature scope or user experience
     - Multiple reasonable interpretations exist with different implications
     - No reasonable default exists
   - **LIMIT: Maximum 3 [NEEDS CLARIFICATION] markers total**
   - Prioritize clarifications by impact: scope > security/privacy > user experience > technical details
4. Fill User Scenarios & Testing section
   If no clear user flow: ERROR "Cannot determine user scenarios"
5. Generate Functional Requirements
   Each requirement must be testable
   Use reasonable defaults for unspecified details (document assumptions in Assumptions section)
6. Define Success Criteria
   Create measurable, technology-agnostic outcomes
   Include both quantitative metrics (time, performance, volume) and qualitative measures (user satisfaction, task completion)
   Each criterion must be verifiable without implementation details
7. Identify Key Entities (if data involved)
8. Return: SUCCESS (spec ready for planning)

Write the specification to SPEC_FILE using the template structure, replacing placeholders with concrete details derived from the feature description (arguments) while preserving section order and headings.

## Quick Guidelines

- Focus on **WHAT** users need and **WHY**.
- Avoid HOW to implement (no tech stack, APIs, code structure).
- Written for business stakeholders, not developers.
- DO NOT create any checklists that are embedded in the spec. That will be a separate command.

### Section Requirements

- **Mandatory sections**: Must be completed for every feature
- **Optional sections**: Include only when relevant to the feature
- When a section doesn't apply, remove it entirely (don't leave as "N/A")

### For AI Generation

When creating this spec from a user prompt:

1. **Make informed guesses**: Use context, industry standards, and common patterns to fill gaps
2. **Document assumptions**: Record reasonable defaults in the Assumptions section
3. **Limit clarifications**: Maximum 3 [NEEDS CLARIFICATION] markers - use only for critical decisions that:
   - Significantly impact feature scope or user experience
   - Have multiple reasonable interpretations with different implications
   - Lack any reasonable default
4. **Prioritize clarifications**: scope > security/privacy > user experience > technical details
5. **Think like a tester**: Every vague requirement should fail the "testable and unambiguous" checklist item
6. **Common areas needing clarification** (only if no reasonable default exists):
   - Feature scope and boundaries (include/exclude specific use cases)
   - User types and permissions (if multiple conflicting interpretations possible)
   - Security/compliance requirements (when legally/financially significant)

**Examples of reasonable defaults** (don't ask about these):

- Data retention: Industry-standard practices for the domain
- Performance targets: Standard web/mobile app expectations unless specified
- Error handling: User-friendly messages with appropriate fallbacks
- Authentication method: Standard session-based or OAuth2 for web apps
- Integration patterns: Use project-appropriate patterns (REST/GraphQL for web services, function calls for libraries, CLI args for tools, etc.)

### Success Criteria Guidelines

Success criteria must be:

1. **Measurable**: Include specific metrics (time, percentage, count, rate)
2. **Technology-agnostic**: No mention of frameworks, languages, databases, or tools
3. **User-focused**: Describe outcomes from user/business perspective, not system internals
4. **Verifiable**: Can be tested/validated without knowing implementation details

**Good examples**:

- "Users can complete checkout in under 3 minutes"
- "System supports 10,000 concurrent users"
- "95% of searches return results in under 1 second"
- "Task completion rate improves by 40%"

**Bad examples** (implementation-focused):

- "API response time is under 200ms" (too technical, use "Users see results instantly")
- "Database can handle 1000 TPS" (implementation detail, use user-facing metric)
- "React components render efficiently" (framework-specific)
- "Redis cache hit rate above 80%" (technology-specific)


## Specification Quality Validation

After writing the initial spec, validate it against quality criteria:

### a. Create Spec Quality Checklist

Generate a checklist file at `FEATURE_DIR/checklists/requirements.md` using the checklist template structure with these validation items:

```markdown
# Specification Quality Checklist: [FEATURE NAME]

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: [DATE]
**Feature**: [Link to spec.md]

## Content Quality

- [ ] No implementation details (languages, frameworks, APIs)
- [ ] Focused on user value and business needs
- [ ] Written for non-technical stakeholders
- [ ] All mandatory sections completed

## Requirement Completeness

- [ ] No [NEEDS CLARIFICATION] markers remain
- [ ] Requirements are testable and unambiguous
- [ ] Success criteria are measurable
- [ ] Success criteria are technology-agnostic (no implementation details)
- [ ] All acceptance scenarios are defined
- [ ] Edge cases are identified
- [ ] Scope is clearly bounded
- [ ] Dependencies and assumptions identified

## Feature Readiness

- [ ] All functional requirements have clear acceptance criteria
- [ ] User scenarios cover primary flows
- [ ] Feature meets measurable outcomes defined in Success Criteria
- [ ] No implementation details leak into specification

## Notes

- Items marked incomplete require spec updates before `/trc.clarify` or `/trc.plan`
```

### b. Run Validation Check

Review the spec against each checklist item:
- For each item, determine if it passes or fails
- Document specific issues found (quote relevant spec sections)

### c. Handle Validation Results

- **If all items pass**: Mark checklist complete and proceed to reporting completion

- **If items fail (excluding [NEEDS CLARIFICATION])**:
  1. List the failing items and specific issues
  2. Update the spec to address each issue
  3. Re-run validation until all items pass (max 3 iterations)
  4. If still failing after 3 iterations, document remaining issues in checklist notes and warn user

- **If [NEEDS CLARIFICATION] markers remain**:
  1. Extract all [NEEDS CLARIFICATION: ...] markers from the spec
  2. **LIMIT CHECK**: If more than 3 markers exist, keep only the 3 most critical (by scope/security/UX impact) and make informed guesses for the rest
  3. For each clarification needed (max 3), present options to user in this format:

     ```markdown
     ## Question [N]: [Topic]

     **Context**: [Quote relevant spec section]

     **What we need to know**: [Specific question from NEEDS CLARIFICATION marker]

     **Suggested Answers**:

     | Option | Answer | Implications |
     |--------|--------|--------------|
     | A      | [First suggested answer] | [What this means for the feature] |
     | B      | [Second suggested answer] | [What this means for the feature] |
     | C      | [Third suggested answer] | [What this means for the feature] |
     | Custom | Provide your own answer | [Explain how to provide custom input] |

     **Your choice**: _[Wait for user response]_
     ```

  4. **CRITICAL - Table Formatting**: Ensure markdown tables are properly formatted:
     - Use consistent spacing with pipes aligned
     - Each cell should have spaces around content: `| Content |` not `|Content|`
     - Header separator must have at least 3 dashes: `|--------|`
     - Test that the table renders correctly in markdown preview
  5. Number questions sequentially (Q1, Q2, Q3 - max 3 total)
  6. Present all questions together before waiting for responses
  7. Wait for user to respond with their choices for all questions (e.g., "Q1: A, Q2: Custom - [details], Q3: B")
  8. Update the spec by replacing each [NEEDS CLARIFICATION] marker with the user's selected or provided answer
  9. Re-run validation after all clarifications are resolved

### d. Update Checklist

After each validation iteration, update the checklist file with current pass/fail status.

## Report Completion

Report completion with branch name, spec file path, checklist results, and readiness for the next phase (`/trc.clarify` or `/trc.plan`).


## Skill Invocations

The following skills are configured for the `specify` step. Invoke each one if installed; skip gracefully if not.

- If `.claude/skills/document-writer/SKILL.md` exists, invoke `/document-writer`. If the skill is not installed, skip this invocation and continue.

Context for invocation: 

