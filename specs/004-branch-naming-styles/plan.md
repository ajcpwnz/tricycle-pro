# Implementation Plan: Configurable Branch Naming Styles

**Branch**: `004-branch-naming-styles` | **Date**: 2026-03-26 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-branch-naming-styles/spec.md`

## Summary

Add configurable branch naming styles to Tricycle Pro. Three styles: `feature-name` (slug from description, new default), `issue-number` (extract/prompt for ticket ID), and `ordered` (current sequential behavior). Changes touch `create-new-feature.sh` (new `--style`/`--issue`/`--prefix` flags), `feature-setup` block (config reading + interactive issue prompting), preset configs (add `branching` section), and tests.

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default), 4.0+ (Linux)
**Primary Dependencies**: Standard Unix utilities (`sed`, `awk`, `grep`, `printf`)
**Storage**: File-based (YAML config, markdown output)
**Testing**: Bash (`tests/run-tests.sh`) + Node.js `node:test` (`tests/test-*.js`)
**Target Platform**: macOS / Linux CLI
**Project Type**: CLI toolkit
**Current Version**: 0.3.0
**Version Bump**: Minor → 0.4.0 (new feature)

## Constitution Check

*Constitution is a placeholder — no gates to enforce.*

## Project Structure

### Documentation (this feature)

```text
specs/004-branch-naming-styles/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── script-interface.md
└── checklists/
    └── requirements.md
```

### Source Code (files to modify/create)

```text
core/scripts/bash/create-new-feature.sh   # Add --style, --issue, --prefix flags
core/blocks/specify/feature-setup.md       # Read branching config, handle issue prompts
presets/single-app/tricycle.config.yml     # Add branching section
presets/nextjs-prisma/tricycle.config.yml  # Add branching section
presets/express-prisma/tricycle.config.yml # Add branching section
presets/monorepo-turborepo/tricycle.config.yml # Add branching section
tests/run-tests.sh                         # Add branch style tests
```

**Structure Decision**: No new files needed. All changes modify existing files in their current locations. The `create-new-feature.sh` script gains new flags; the `feature-setup` block gains config-reading logic; preset configs gain a new `branching` section.

## Design

### 1. Script Changes (`create-new-feature.sh`)

The script currently always uses `ordered` style (numeric prefix). Refactor the branch naming section into three code paths gated by `--style`:

- **`feature-name`**: Skip number detection entirely. Use `generate_branch_name()` or `--short-name` directly. No `FEATURE_NUM` prefix.
- **`issue-number`**: Extract issue ID from description using `--prefix` regex or generic pattern. If not found, exit code 2. Prepend issue ID to slug.
- **`ordered`**: Current behavior unchanged.

The `--style` flag defaults to `ordered` when not passed, preserving backward compatibility for direct script invocation. The `feature-setup` block is responsible for reading config and passing the right `--style`.

### 2. Block Changes (`feature-setup.md`)

The block currently always calls the script with `--short-name` and no style flag. Updated flow:

1. Read `branching.style` from `tricycle.config.yml` (via the agent reading the file — blocks are markdown, not bash).
2. Read `branching.prefix` if style is `issue-number`.
3. For `issue-number`: scan the user's description for the issue pattern. If found, pass `--issue <ID>`. If not found, ask the user and wait for response, then pass `--issue <response>`.
4. Pass `--style <style>` to the script.

### 3. Config Changes (presets)

Add `branching` section to all preset configs with `style: feature-name` as default. The `ordered` style is available but not the default for new projects.

### 4. Test Changes

Add test cases to `tests/run-tests.sh`:
- `feature-name` style produces slug-only branch
- `ordered` style produces `###-slug` branch (regression)
- `--style` flag is accepted without error
- Missing `--style` defaults to `ordered`
