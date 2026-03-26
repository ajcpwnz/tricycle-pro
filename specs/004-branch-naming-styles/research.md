# Research: Configurable Branch Naming Styles

## R1: Branch Naming Conventions in the Wild

**Decision**: Support three styles — `feature-name`, `issue-number`, `ordered`.

**Rationale**: These cover the three dominant patterns seen across open source and enterprise projects:
1. **Slug-based** (`feature-name`): Used by most small/medium projects. GitHub's default "Create a branch" UI generates these. No coordination needed.
2. **Issue-prefixed** (`issue-number`): Standard in Jira/Linear/Shortcut workflows. Branch names like `TRI-042-export-csv` link directly to tickets. Many CI/CD systems auto-detect these prefixes.
3. **Sequential** (`ordered`): Used by projects that want a linear feature history. Tricycle Pro's current behavior.

**Alternatives considered**:
- **Fully custom regex-based naming**: Too complex for config, error-prone. The three styles cover 95%+ of use cases.
- **Date-based prefixes** (e.g., `2026-03-26-feature`): Rarely used, can be achieved with `feature-name` + manual `--short-name`.

## R2: Issue Number Extraction from Natural Language

**Decision**: Use prefix-based regex matching. When `branch_prefix` is configured, match `<PREFIX>-<DIGITS>` case-insensitively. When no prefix is configured, match the generic pattern `[A-Z]+-\d+`.

**Rationale**: The prefix is always a sequence of uppercase letters followed by a hyphen and digits. This is universal across Jira (`PROJ-123`), Linear (`TRI-42`), Shortcut (`sc-1234`), and GitHub Issues (`GH-456`). Case-insensitive matching handles user typos like `tri-042`.

**Alternatives considered**:
- **NLP-based extraction**: Overkill for a bash script. Regex handles all realistic formats.
- **Strict prefix-only matching**: Too rigid. Generic fallback handles projects that haven't configured a prefix yet.

## R3: Where Style Config Lives

**Decision**: New `branching` section in `tricycle.config.yml` with `style` and `prefix` keys.

**Rationale**: Follows the existing config pattern (like `worktree`, `push`, `qa` sections). Keeps all project configuration in one place. The YAML parser already handles nested keys via `parse_yaml` → `cfg_get("branching.style")`.

**Alternatives considered**:
- **Top-level `branch_style` key**: Breaks the nested-section convention used everywhere else.
- **Separate `.tricycle-branching.yml` file**: Unnecessary fragmentation for two config values.

## R4: How the Feature-Setup Block Communicates Style to the Script

**Decision**: The `feature-setup` block reads `branching.style` from config using the `parse_yaml`/`cfg_get` functions already available in `common.sh` (sourced by `create-new-feature.sh`), and passes `--style <value>` to the script. For `issue-number`, the block also handles the interactive prompt if no issue number is found.

**Rationale**: The script handles branch creation mechanics. The block (markdown executed by the agent) handles interactive prompts. This separation keeps the script non-interactive (a core principle) while the agent handles the conversation.

**Alternatives considered**:
- **Script reads config directly**: Already possible since it sources `common.sh`, but the block should be the orchestrator that decides what flags to pass.
- **Script prompts for issue number**: Violates the non-interactive principle. The agent should ask, then pass the answer to the script.
