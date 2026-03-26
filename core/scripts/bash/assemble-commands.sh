#!/usr/bin/env bash
set -e

# ─── Assembly Script ──────────────────────────────────────────────────────
# Assembles block files into command files based on workflow chain and block config.
# Usage: assemble-commands.sh [--dry-run] [--verbose] [--blocks-dir DIR] [--output-dir DIR] [--config FILE]

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ─── Defaults ─────────────────────────────────────────────────────────────

REPO_ROOT=$(get_repo_root)
DRY_RUN=0
VERBOSE=0
BLOCKS_DIR="$REPO_ROOT/core/blocks"
OUTPUT_DIR="$REPO_ROOT/core/commands"
CONFIG_FILE="$REPO_ROOT/tricycle.config.yml"
CANONICAL_CHAIN="specify plan tasks implement"
HEADLESS_SOURCE="$REPO_ROOT/core/commands/trc.headless.md"

# ─── Argument parsing ─────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=1 ;;
        --verbose)  VERBOSE=1 ;;
        --blocks-dir=*) BLOCKS_DIR="${arg#*=}" ;;
        --output-dir=*) OUTPUT_DIR="${arg#*=}" ;;
        --config=*)     CONFIG_FILE="${arg#*=}" ;;
        --help|-h)
            echo "Usage: assemble-commands.sh [--dry-run] [--verbose] [--config=FILE]"
            exit 0 ;;
    esac
done

# ─── Handoff definitions per step ─────────────────────────────────────────

get_step_description() {
    case "$1" in
        specify)   echo "Create or update the feature specification from a natural language feature description." ;;
        plan)      echo "Execute the implementation planning workflow using the plan template to generate design artifacts." ;;
        tasks)     echo "Generate an actionable, dependency-ordered tasks.md for the feature based on available design artifacts." ;;
        implement) echo "Execute the implementation plan by processing and executing all tasks defined in tasks.md" ;;
    esac
}

# Generate handoffs YAML based on the next step in the chain
get_step_handoffs() {
    local step="$1"
    local chain="$2"
    local steps=()
    read -ra steps <<< "$chain"

    # Find the next step after this one in the chain
    local found=0
    local next_step=""
    for s in "${steps[@]}"; do
        if [[ $found -eq 1 ]]; then
            next_step="$s"
            break
        fi
        [[ "$s" == "$step" ]] && found=1
    done

    case "$step" in
        specify)
            cat << 'YAML'
handoffs:
  - label: Build Technical Plan
    agent: trc.plan
    prompt: Create a plan for the spec. I am building with...
  - label: Clarify Spec Requirements
    agent: trc.clarify
    prompt: Clarify specification requirements
    send: true
YAML
            ;;
        plan)
            if [[ "$next_step" == "tasks" ]]; then
                cat << 'YAML'
handoffs:
  - label: Create Tasks
    agent: trc.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: trc.checklist
    prompt: Create a checklist for the following domain...
YAML
            else
                cat << 'YAML'
handoffs:
  - label: Implement Project
    agent: trc.implement
    prompt: Start the implementation in phases
    send: true
  - label: Create Checklist
    agent: trc.checklist
    prompt: Create a checklist for the following domain...
YAML
            fi
            ;;
        tasks)
            cat << 'YAML'
handoffs:
  - label: Analyze For Consistency
    agent: trc.analyze
    prompt: Run a project analysis for consistency
    send: true
  - label: Implement Project
    agent: trc.implement
    prompt: Start the implementation in phases
    send: true
YAML
            ;;
        implement)
            # implement has no handoffs
            ;;
    esac
}

# ─── Core assembly functions ──────────────────────────────────────────────

# Collect enabled blocks for a step, applying overrides and absorption.
# Outputs lines: ORDER|FILE_PATH|BLOCK_NAME|SOURCE (where SOURCE is "own", "absorbed:STEP", etc.)
collect_blocks_for_step() {
    local step="$1"
    local chain="$2"
    local config_file="$3"
    local blocks_dir="$4"

    # 1. Collect own blocks
    local block_file
    while IFS= read -r block_file; do
        [[ -z "$block_file" ]] && continue
        local name order required default_enabled
        name=$(get_block_field "$block_file" "name")
        order=$(get_block_field "$block_file" "order")
        required=$(get_block_field "$block_file" "required")
        default_enabled=$(get_block_field "$block_file" "default_enabled")

        [[ "$default_enabled" != "true" && "$required" != "true" ]] && continue
        printf '%s|%s|%s|own\n' "$order" "$block_file" "$name"
    done < <(list_blocks_for_step "$blocks_dir" "$step")

    # 2. Collect absorbed blocks from omitted steps
    local canonical=()
    read -ra canonical <<< "$CANONICAL_CHAIN"
    local chain_steps=()
    read -ra chain_steps <<< "$chain"

    local absorption_offset=100
    for canon_step in "${canonical[@]}"; do
        # Skip if step is in chain
        local in_chain=0
        for cs in "${chain_steps[@]}"; do
            [[ "$cs" == "$canon_step" ]] && in_chain=1 && break
        done
        [[ $in_chain -eq 1 ]] && continue

        # Determine absorption target: the preceding step in canonical order that IS in the chain
        local target=""
        for cs in "${canonical[@]}"; do
            [[ "$cs" == "$canon_step" ]] && break
            local cs_in_chain=0
            for cs2 in "${chain_steps[@]}"; do
                [[ "$cs2" == "$cs" ]] && cs_in_chain=1 && break
            done
            [[ $cs_in_chain -eq 1 ]] && target="$cs"
        done

        # Only absorb into the current step
        [[ "$target" != "$step" ]] && continue

        # Collect non-required default-enabled blocks from omitted step
        while IFS= read -r block_file; do
            [[ -z "$block_file" ]] && continue
            local name order required default_enabled
            name=$(get_block_field "$block_file" "name")
            order=$(get_block_field "$block_file" "order")
            required=$(get_block_field "$block_file" "required")
            default_enabled=$(get_block_field "$block_file" "default_enabled")

            # Skip required blocks (infrastructure) and non-default blocks
            [[ "$required" == "true" ]] && continue
            [[ "$default_enabled" != "true" ]] && continue

            local adjusted_order=$((order + absorption_offset))
            printf '%s|%s|%s|absorbed:%s\n' "$adjusted_order" "$block_file" "$name" "$canon_step"
        done < <(list_blocks_for_step "$blocks_dir" "$canon_step")

        absorption_offset=$((absorption_offset + 100))
    done

    # 3. Apply overrides from config
    # (Override application happens in assemble_step after collecting)
}

# Apply block overrides (disable/enable/custom) to collected blocks.
# Takes collected blocks on stdin, outputs filtered blocks.
apply_overrides() {
    local step="$1"
    local config_file="$2"
    local blocks_dir="$3"

    local overrides=""
    overrides=$(parse_block_overrides "$config_file" "$step")

    # Read all collected blocks into array
    local blocks=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        blocks+=("$line")
    done

    # Get disable list
    local disabled=()
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        disabled+=("$item")
    done < <(echo "$overrides" | grep '^disable=' | cut -d= -f2-)

    # Get enable list (for optional blocks)
    local enabled=()
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        enabled+=("$item")
    done < <(echo "$overrides" | grep '^enable=' | cut -d= -f2-)

    # Get custom block paths
    local customs=()
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        customs+=("$item")
    done < <(echo "$overrides" | grep '^custom=' | cut -d= -f2-)

    # Filter out disabled blocks
    for block_line in "${blocks[@]}"; do
        local block_name
        block_name=$(echo "$block_line" | cut -d'|' -f3)
        local is_disabled=0
        for d in "${disabled[@]}"; do
            [[ "$d" == "$block_name" ]] && is_disabled=1 && break
        done
        [[ $is_disabled -eq 0 ]] && echo "$block_line"
    done

    # Add enabled optional blocks
    for en in "${enabled[@]}"; do
        local opt_file="$blocks_dir/optional/$step/$en.md"
        if [[ -f "$opt_file" ]]; then
            local order
            order=$(get_block_field "$opt_file" "order")
            printf '%s|%s|%s|enabled\n' "$order" "$opt_file" "$en"
        fi
    done

    # Add companion-enabled blocks
    if [[ -n "$COMPANION_ENABLES" ]]; then
        for comp in $COMPANION_ENABLES; do
            local comp_step="${comp%%:*}"
            local comp_block="${comp#*:}"
            if [[ "$comp_step" == "$step" ]]; then
                # Check if already present
                local already=0
                for en in "${enabled[@]}"; do
                    [[ "$en" == "$comp_block" ]] && already=1 && break
                done
                if [[ $already -eq 0 ]]; then
                    local opt_file="$blocks_dir/optional/$step/$comp_block.md"
                    if [[ -f "$opt_file" ]]; then
                        local order
                        order=$(get_block_field "$opt_file" "order")
                        printf '%s|%s|%s|companion\n' "$order" "$opt_file" "$comp_block"
                    fi
                fi
            fi
        done
    fi

    # Add custom blocks
    for custom_path in "${customs[@]}"; do
        local full_path="$custom_path"
        [[ ! "$custom_path" = /* ]] && full_path="$(get_repo_root)/$custom_path"
        if [[ -f "$full_path" ]]; then
            local name order
            name=$(get_block_field "$full_path" "name")
            order=$(get_block_field "$full_path" "order")
            printf '%s|%s|%s|custom\n' "$order" "$full_path" "$name"
        else
            echo "ERROR: Custom block not found: $custom_path" >&2
            exit 1
        fi
    done
}

# Assemble a single step's command file from blocks.
assemble_step() {
    local step="$1"
    local chain="$2"
    local config_file="$3"
    local blocks_dir="$4"
    local output_dir="$5"
    local output_file="$output_dir/trc.${step}.md"

    # Collect and sort blocks
    local sorted_blocks
    sorted_blocks=$(collect_blocks_for_step "$step" "$chain" "$config_file" "$blocks_dir" | \
        apply_overrides "$step" "$config_file" "$blocks_dir" | \
        sort -t'|' -k1 -n)

    local block_count
    block_count=$(echo "$sorted_blocks" | grep -c '|' || true)

    if [[ $VERBOSE -eq 1 ]] || [[ $DRY_RUN -eq 1 ]]; then
        echo ""
        echo "Step: $step ($block_count blocks)"
        echo "$sorted_blocks" | while IFS='|' read -r order file name source; do
            local marker="✓"
            [[ "$source" == absorbed:* ]] && marker="+"
            [[ "$source" == "enabled" ]] && marker="⊕"
            [[ "$source" == "companion" ]] && marker="⊕"
            [[ "$source" == "custom" ]] && marker="◆"
            local req=""
            local is_req
            is_req=$(get_block_field "$file" "required")
            [[ "$is_req" == "true" ]] && req=" (required)"
            echo "  $marker $name ($source, order: $order)$req"
        done
        echo "  → $output_file"
    fi

    [[ $DRY_RUN -eq 1 ]] && return 0

    # Generate the command file
    {
        # YAML frontmatter
        echo "---"
        echo "description: $(get_step_description "$step")"
        get_step_handoffs "$step" "$chain"
        echo "---"
        echo ""

        # User Input section (always first)
        echo "## User Input"
        echo ""
        echo '```text'
        echo '$ARGUMENTS'
        echo '```'
        echo ""
        echo 'You **MUST** consider the user input before proceeding (if not empty).'
        echo ""

        # Concatenate block content
        local prev_source=""
        echo "$sorted_blocks" | while IFS='|' read -r order file name source; do
            [[ -z "$file" ]] && continue
            # Add absorption separator
            if [[ "$source" == absorbed:* ]] && [[ "$prev_source" != "$source" ]]; then
                local from_step="${source#absorbed:}"
                echo ""
                echo "<!-- Absorbed from ${from_step} step -->"
                echo ""
            fi
            read_block_content "$file"
            echo ""
            prev_source="$source"
        done
    } > "$output_file"
}

# Generate a blocked stub for steps not in the chain.
generate_blocked_stub() {
    local step="$1"
    local chain="$2"
    local output_dir="$3"
    local output_file="$output_dir/trc.${step}.md"

    if [[ $VERBOSE -eq 1 ]] || [[ $DRY_RUN -eq 1 ]]; then
        echo ""
        echo "Step: $step (BLOCKED — not in chain)"
        echo "  → $output_file (stub)"
    fi

    [[ $DRY_RUN -eq 1 ]] && return 0

    local chain_display
    chain_display=$(echo "$chain" | tr ' ' ', ')

    cat > "$output_file" << EOF
---
description: "Step '${step}' is not in the configured workflow chain."
---

## User Input

\`\`\`text
\$ARGUMENTS
\`\`\`

## Blocked

**Error**: The \`${step}\` step is not part of the configured workflow chain.

**Current chain**: [${chain_display}]

To use this step, update \`workflow.chain\` in \`tricycle.config.yml\` to include \`${step}\`, then run \`tricycle assemble\` to regenerate command files.

Valid chain configurations:
- \`[specify, plan, tasks, implement]\` (default — full workflow)
- \`[specify, plan, implement]\` (tasks absorbed into plan)
- \`[specify, implement]\` (plan and tasks absorbed into specify)
EOF
}

# Generate headless command from chain.
generate_headless() {
    local chain="$1"
    local output_dir="$2"
    local output_file="$output_dir/trc.headless.md"

    local steps=()
    read -ra steps <<< "$chain"
    local total=${#steps[@]}

    if [[ $VERBOSE -eq 1 ]] || [[ $DRY_RUN -eq 1 ]]; then
        echo ""
        echo "Headless: $total phases ($(echo "$chain" | tr ' ' ' → '))"
        echo "  → $output_file"
    fi

    [[ $DRY_RUN -eq 1 ]] && return 0

    {
        cat << 'FRONTMATTER'
---
description: >-
  Run the full workflow chain automatically from a single prompt.
  Pauses only for critical clarifications, destructive actions, or push approval.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Flight Validation

Before executing the chain, validate all prerequisites:

1. **Empty prompt check**: If the user input above is empty or only
   whitespace, STOP immediately and output:
   ```
   Error: No feature description provided.
   Usage: /trc.headless <feature description>
   ```
   Do NOT proceed with any phase.

2. **Project initialization check**: Verify that `tricycle.config.yml`
   exists in the project root AND that the `.trc/` directory exists.
   If either is missing, STOP immediately and output:
   ```
   Error: Tricycle Pro not initialized.
   Run `npx tricycle-pro init` to set up the project.
   ```

3. **Partial artifact check**: Check if a spec directory already exists
   for a feature matching the user's description. If found, warn the
   user and ask whether to resume from the last completed phase or
   start fresh. Wait for their response before proceeding.

## Headless Execution Mode

This command runs the **complete** workflow chain in a single invocation.
The key behavioral differences from running each command manually:

- **Auto-continue**: Phase transitions happen automatically. Do NOT
  wait for user input between phases.
- **Auto-resolve**: Non-critical clarifications during the specify
  phase MUST be resolved with informed guesses and reasonable
  defaults. Only pause for critical ambiguities (see Pause Rules).
- **Auto-proceed checklists**: If all checklist items pass, proceed
  without asking. Only pause if checklist items fail.
- **Constitution enforcement**: All constitution principles remain
  active. Lint/test gates (Principle II) and push approval
  (Principle III) are NEVER bypassed.

## Phase Execution

Execute these phases in strict order. Each phase MUST complete
fully and produce its standard artifacts before the next begins.

FRONTMATTER

        # Generate phase sections
        local phase_num=1
        for step in "${steps[@]}"; do
            local step_upper
            step_upper=$(echo "$step" | tr '[:lower:]' '[:upper:]' | head -c1)$(echo "$step" | tail -c+2)
            echo "### --- Phase ${phase_num}/${total}: ${step_upper} --- starting..."
            echo ""
            echo "Invoke \`/trc.${step}\` with the user's input as the feature description."
            echo ""
            echo "**Headless behavior overrides**:"

            case "$step" in
                specify)
                    cat << 'EOF'
- When generating the spec, auto-resolve non-critical clarifications
  with informed guesses. Document assumptions in the spec rather than
  pausing for input.
- The 3-clarification limit from `/trc.specify` applies. If any
  `[NEEDS CLARIFICATION]` markers remain that are genuinely critical
  (scope-impacting ambiguity where multiple interpretations lead to
  fundamentally different features), PAUSE and present the question
  to the user. Otherwise, resolve with the most reasonable default.
- Auto-proceed through checklist validation if all items pass.
EOF
                    ;;
                plan)
                    cat << 'EOF'
- Do NOT wait for user input after the plan is generated.
- If the plan phase asks for technology choices or framework
  preferences, infer from the existing project context
  (tricycle.config.yml, package.json, existing code).
- Auto-continue to the next phase.
EOF
                    ;;
                tasks)
                    cat << 'EOF'
- Do NOT wait for user input after tasks are generated.
- Auto-continue to the next phase.
EOF
                    ;;
                implement)
                    cat << 'EOF'
- Execute all task phases as defined in tasks.md.
- If lint or tests fail, attempt to diagnose and fix the issue.
  Retry up to 3 times. If still failing after 3 attempts, PAUSE
  and report the failure to the user (see Pause Rules below).
- Do NOT push code or create a PR. After implementation completes,
  pause for push approval per constitution Principle III.
EOF
                    ;;
            esac

            echo "- After ${step} completes, output:"
            echo "  \`\`\`"
            echo "  --- Phase ${phase_num}/${total}: ${step_upper} --- complete"
            echo "  \`\`\`"
            echo ""
            phase_num=$((phase_num + 1))
        done

        # Pause rules and completion summary
        cat << 'FOOTER'
## Pause Rules

During headless execution, you MUST pause and wait for user input
ONLY in these situations:

### 1. Critical Clarification

A spec ambiguity where:
- No reasonable default exists
- Multiple interpretations lead to fundamentally different features
- The choice significantly impacts scope, security, or user experience

When pausing for clarification:
- Present the question with concrete options (A, B, C, Custom)
- Wait for the user's response
- Incorporate their answer into the spec
- Resume the chain from where it paused

### 2. Destructive or Irreversible Action

An operation that cannot be undone:
- Deleting files outside the feature's spec directory
- Resetting branches or discarding uncommitted changes
- Database migrations or schema changes
- Overwriting existing code not created by this headless run

When pausing for destructive actions:
- Describe exactly what will be done
- Wait for explicit user approval
- Resume the chain from where it paused

### 3. Push Approval (NEVER auto-resolved)

Per constitution Principle III, pushing code or creating PRs
ALWAYS requires explicit user approval. This is non-negotiable.

When the chain completes:
- Display the completion summary (see below)
- State readiness to push
- Wait for the user to say "push", "go ahead", or equivalent
- Each push requires fresh confirmation

### 4. Lint/Test Failure After Retries

If lint or tests fail and 3 fix attempts have been exhausted:
- Report the failure clearly
- Show what passed and what failed
- Suggest next steps
- Wait for user to decide how to proceed

**Resume behavior**: After ANY pause, resume the chain from the
exact point where it paused. Do NOT restart the current phase
or skip ahead to the next phase.

## Completion Summary

When all phases complete successfully, output:

```
--- Headless Run Complete ---

Branch: [branch-name]
Artifacts:
  - specs/[NNN-feature]/spec.md
  - specs/[NNN-feature]/plan.md
  - specs/[NNN-feature]/research.md
  - specs/[NNN-feature]/data-model.md
  - specs/[NNN-feature]/tasks.md
  - [list implementation files created/modified]

Lint: [PASS/FAIL]
Tests: [PASS/FAIL]

Next: Push approval required. Say "push" when ready.
```

## Failure Summary

If the chain fails at any phase and cannot recover, output:

```
--- Headless Run Failed ---

Failed at: Phase N/M ([Phase Name])
Error: [description of what went wrong]
Completed artifacts:
  - [list of artifacts successfully produced]
Suggested next steps:
  - [actionable suggestions for the user]
```
FOOTER
    } > "$output_file"
}

# ─── Companion resolution ─────────────────────────────────────────────────

# COMPANION_ENABLES is a global associative-style list: "step:block step:block ..."
COMPANION_ENABLES=""

# Scan all enabled blocks across all steps for companion declarations.
# Populates COMPANION_ENABLES with "step:block" entries to auto-enable.
resolve_companions() {
    local chain="$1"
    local config_file="$2"
    local blocks_dir="$3"

    local chain_steps=()
    read -ra chain_steps <<< "$chain"

    for step in "${chain_steps[@]}"; do
        # Collect blocks that will be enabled for this step
        local enabled_blocks
        enabled_blocks=$(collect_blocks_for_step "$step" "$chain" "$config_file" "$blocks_dir" | \
            apply_overrides "$step" "$config_file" "$blocks_dir")

        # Also check explicitly enabled optional blocks
        local overrides
        overrides=$(parse_block_overrides "$config_file" "$step")
        local enable_list=""
        enable_list=$(echo "$overrides" | grep '^enable=' | cut -d= -f2-)

        # For each enabled block (own + explicitly enabled), check companions field
        local all_files=""
        all_files=$(echo "$enabled_blocks" | cut -d'|' -f2)
        while IFS= read -r en_name; do
            [[ -z "$en_name" ]] && continue
            local opt_file="$blocks_dir/optional/$step/$en_name.md"
            [[ -f "$opt_file" ]] && all_files="$all_files"$'\n'"$opt_file"
        done <<< "$enable_list"

        while IFS= read -r block_file; do
            [[ -z "$block_file" ]] && continue
            [[ ! -f "$block_file" ]] && continue
            local companions
            companions=$(get_block_field "$block_file" "companions")
            if [[ -n "$companions" ]]; then
                # companions format: "step:block" or "step:block step:block"
                for comp in $companions; do
                    # Deduplicate
                    case " $COMPANION_ENABLES " in
                        *" $comp "*) ;;  # already present
                        *) COMPANION_ENABLES="$COMPANION_ENABLES $comp" ;;
                    esac
                done
            fi
        done <<< "$all_files"
    done
}

# Check if a block should be auto-enabled via companion resolution.
# Returns 0 (true) if the block should be enabled, 1 otherwise.
is_companion_enabled() {
    local step="$1"
    local block_name="$2"
    local target="${step}:${block_name}"

    for comp in $COMPANION_ENABLES; do
        [[ "$comp" == "$target" ]] && return 0
    done
    return 1
}

# ─── Main ─────────────────────────────────────────────────────────────────

main() {
    # Read chain config
    local chain
    chain=$(parse_chain_config "$CONFIG_FILE")

    # Validate chain
    if ! validate_chain "$chain"; then
        exit 1
    fi

    local chain_steps=()
    read -ra chain_steps <<< "$chain"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "Chain: [$(echo "$chain" | tr ' ' ', ')]"
    fi

    # Resolve companion blocks (must happen before assembly)
    resolve_companions "$chain" "$CONFIG_FILE" "$BLOCKS_DIR"

    # Assemble each step in the chain
    for step in "${chain_steps[@]}"; do
        assemble_step "$step" "$chain" "$CONFIG_FILE" "$BLOCKS_DIR" "$OUTPUT_DIR"
    done

    # Generate blocked stubs for omitted steps
    local canonical=()
    read -ra canonical <<< "$CANONICAL_CHAIN"
    for canon_step in "${canonical[@]}"; do
        local in_chain=0
        for cs in "${chain_steps[@]}"; do
            [[ "$cs" == "$canon_step" ]] && in_chain=1 && break
        done
        [[ $in_chain -eq 0 ]] && generate_blocked_stub "$canon_step" "$chain" "$OUTPUT_DIR"
    done

    # Generate headless command
    generate_headless "$chain" "$OUTPUT_DIR"

    if [[ $DRY_RUN -eq 0 ]]; then
        local assembled=${#chain_steps[@]}
        local blocked=$((4 - assembled))
        echo ""
        echo "Assembly complete: $assembled steps assembled, $blocked blocked, 1 headless generated."
    fi
}

main
