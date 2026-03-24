# Research: Shell-Only CLI

## R1: YAML Subset Parsing in Bash

**Decision**: Implement a line-by-line `awk`-based YAML parser that converts the constrained YAML subset into flat key-value pairs using dot-notation keys (e.g., `project.name=tricycle-pro`, `apps.0.docker.compose=docker-compose.yml`).

**Rationale**: The YAML used in `tricycle.config.yml` is a constrained subset — no anchors, aliases, multi-document streams, or block scalars. The most complex structures are: nested objects, arrays of objects (detected by leading `- `), simple string arrays (inline `["a", "b"]` syntax), booleans, comments, and quoted strings. An `awk` script can track indentation depth to determine nesting, detect array item starts (lines beginning with `- ` at a given indent), and emit flat key-value pairs. This avoids needing Python, Ruby, or any external dependency.

**Alternatives considered**:
- **Python/Ruby one-liner**: Adds a runtime dependency, violates FR-001.
- **`sed` pipeline**: Too fragile for nested structures and arrays of objects.
- **Pure bash `read` loop**: Possible but slow and harder to handle indentation tracking vs `awk`.
- **Convert config to shell format**: Would break compatibility with existing configs (FR-004).

**YAML features the parser MUST handle** (based on actual preset files):
- Scalar values: `name: tricycle-pro` (quoted and unquoted)
- Nested objects: `project:\n  name: value`
- Arrays of objects: `apps:\n  - name: backend\n    path: apps/backend`
- Deeply nested objects within array items: `apps[0].docker.compose`
- Inline JSON-style arrays: `args: ["prisma", "mcp"]`
- Simple value arrays: `env_copy:\n    - apps/backend/.env`
- Booleans: `true`, `false`
- Comments: lines starting with `#` (strip)
- Empty/blank lines (skip)

**YAML features NOT supported** (confirmed not used):
- Anchors & aliases (`&`, `*`)
- Multi-line block scalars (`|`, `>`)
- Flow mappings (`{key: value}`)
- Multi-document (`---`)
- Null values
- Numeric types (treated as strings)

## R2: JSON Generation in Bash

**Decision**: Build JSON output using `printf` and string concatenation with helper functions for escaping, object construction, and array construction.

**Rationale**: The CLI generates three JSON files: `.claude/settings.json`, `.mcp.json`, and `.tricycle.lock`. All have known, fixed structures — not arbitrary depth. Helper functions like `json_string()`, `json_array()`, `json_object_start/end()` can handle escaping and comma placement. This is simpler than trying to manipulate raw JSON strings.

**Alternatives considered**:
- **`jq`**: Not universally installed (macOS doesn't ship it). Adding it as a dependency contradicts FR-001.
- **`python -c 'import json'`**: Adds Python dependency.
- **Heredoc templates**: Works for fixed structures but breaks when content needs escaping.

**Escaping requirements**: Only double quotes and backslashes need escaping in the values we produce. No user-controlled freeform text enters JSON — all values come from config parsing or computed checksums.

## R3: Handlebars-Like Template Substitution in Bash

**Decision**: Implement template processing using `sed` for simple variable substitution (`{{var}}`), and `awk` for block constructs (`{{#each}}`, `{{#if}}`).

**Rationale**: Three constructs are used across the 9 template files:
1. `{{project.name}}` — simple variable replacement → `sed` with captured config values
2. `{{#each apps}}...{{/each}}` — loop over apps array → `awk` extracts the block, iterates over app count, substitutes per-app variables
3. `{{#if key}}...{{/if}}` — conditional inclusion → `awk` checks if key is truthy in parsed config, includes or omits block

The template files are small (5-20 lines each) and the syntax is minimal. A two-pass approach works: first pass resolves `{{#each}}` and `{{#if}}` blocks, second pass substitutes remaining `{{var}}` placeholders.

**Alternatives considered**:
- **`envsubst`**: Only handles `$VAR` syntax, no loops or conditionals.
- **`m4`**: Powerful but different syntax, would require rewriting all templates.
- **Custom template format**: Breaks FR-008 (must use same template syntax).

## R4: SHA-256 Cross-Platform Detection

**Decision**: Try `sha256sum` first (Linux), fall back to `shasum -a 256` (macOS). Cache the detected command in a variable at startup.

**Rationale**: macOS ships `shasum` (Perl-based), Linux ships `sha256sum` (coreutils). Both output in the same format: `<hash>  <filename>`. Detect once at CLI startup and reuse.

**Implementation**:
```
if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  SHA_CMD="shasum -a 256"
else
  error "No SHA-256 tool found"
fi
```

## R5: One-Off Execution Bootstrapper

**Decision**: Provide a lightweight `install.sh` script that can be curled and piped to bash. It clones the repo to a temporary directory, runs the requested subcommand, and cleans up (for one-off mode) or installs to a user-specified location (for persistent install).

**Rationale**: Two modes needed:
1. **One-off**: `bash <(curl -sL <url>) init --preset single-app` — clones to `/tmp`, runs command, cleans up.
2. **Install**: `bash <(curl -sL <url>) --install [path]` — clones to target path (default `~/.tricycle-pro`), creates symlink in `~/.local/bin/` or prints PATH instructions.

**Alternatives considered**:
- **Single self-contained script**: Would require embedding all templates, presets, and modules inline — impractical given the file tree size.
- **tar.gz download**: Requires hosting binary releases, more infrastructure than needed.
- **Git submodule in user project**: Too invasive for a scaffolding tool.

## R6: Test Strategy Implementation

**Decision**: Plain shell test scripts in `tests/` using `test`/`[` assertions, a minimal test runner function, and temp directory isolation.

**Rationale**: Each test creates a temp directory, runs the CLI command, checks outputs with `[ -f file ]`, `grep`, and string comparison, then cleans up. A `run_test()` helper function tracks pass/fail counts. This mirrors the existing Node.js test coverage (CLI operations, file integrity, init/add/generate workflows) without external dependencies.

**Test file structure**:
- `tests/run-tests.sh` — test runner entry point
- Tests organized as functions within the runner, matching current test groups: CLI basics, file integrity, init with presets, init errors, add modules, generate commands
