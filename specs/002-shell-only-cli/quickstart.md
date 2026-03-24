# Quickstart: Shell-Only CLI Development

## Prerequisites

- bash 3.2+ (macOS default) or bash 4.0+ (Linux)
- Standard Unix utilities: `sed`, `awk`, `grep`, `find`, `chmod`, `mkdir`, `cat`
- `shasum` (macOS) or `sha256sum` (Linux)
- Git (for version control and one-off bootstrapper)

## Repository Layout (post-migration)

```
bin/
├── tricycle                # Main CLI entry point (bash)
└── lib/
    ├── yaml_parser.sh      # YAML subset → flat key-value pairs
    ├── json_builder.sh     # JSON output helpers
    ├── template_engine.sh  # {{var}}, {{#each}}, {{#if}} processor
    └── helpers.sh          # Checksum, file ops, prompts, install helpers

install.sh                  # Bootstrapper for one-off + install modes

tests/
└── run-tests.sh            # Test runner (plain shell assertions)

# Unchanged directories:
core/                       # Commands, hooks, templates, scripts, skills
generators/sections/         # CLAUDE.md template sections
modules/                    # Optional add-on modules
presets/                    # Preset configurations
```

## Running the CLI Locally

```bash
# From repo root
./bin/tricycle --help
./bin/tricycle init --preset single-app
./bin/tricycle validate

# Or symlink for global use
ln -s "$(pwd)/bin/tricycle" ~/.local/bin/tricycle
```

## Running Tests

```bash
./tests/run-tests.sh
```

## Key Design Decisions

1. **YAML parser outputs flat key-value pairs** — `project.name=tricycle-pro`, `apps.0.name=backend`. All config access goes through a `cfg_get <key>` helper that looks up these flat pairs.

2. **JSON is built with printf helpers** — no `jq` dependency. Helper functions handle escaping and structure.

3. **Template engine is two-pass** — first pass resolves `{{#each}}` and `{{#if}}` blocks with `awk`, second pass substitutes `{{variable}}` placeholders with `sed`.

4. **Library files are sourced** — `bin/tricycle` sources `bin/lib/*.sh` at startup. This keeps the code modular and testable while remaining a single-entry-point CLI.

5. **Bash 3.2 compatibility** — no associative arrays (bash 4+), no `mapfile` (bash 4+). Config stored as newline-delimited `KEY=VALUE` string, searched with `grep`.
