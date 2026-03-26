---
name: feature-setup
step: specify
description: Create feature branch and initialize spec file via create-new-feature.sh
required: true
default_enabled: true
order: 10
---

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
