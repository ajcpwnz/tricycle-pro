#!/usr/bin/env bash
set -eo pipefail

# Assembles block files into the /trc.plan and /trc.implement command files.
# Usage: assemble-commands.sh [--dry-run] [--verbose] [--blocks-dir=DIR] [--output-dir=DIR] [--config=FILE]
#
# A step's command is its blocks, sorted by `order`:
#   - blocks/<step>/*.md with `default_enabled: true` or `required: true`;
#   - blocks/optional/<step>/<name>.md when enabled;
#   - custom block files listed under workflow.blocks.<step>.custom.
# workflow.blocks.<step>.enable / .disable switch blocks on and off (a required
# block cannot be disabled). worktree.enabled switches worktree-setup and
# worktree-cleanup, qa.enabled switches qa-testing.
#
# models.<step> sets the command's `model:` frontmatter. Block text may use
# {{models.workers}} and {{models.validator}}; each is replaced by its config
# value. Values are Claude Code model aliases: fable, opus, sonnet, haiku.

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REPO_ROOT=$(get_repo_root)
DRY_RUN=0
VERBOSE=0
BLOCKS_DIR="$REPO_ROOT/core/blocks"
OUTPUT_DIR="$REPO_ROOT/core/commands"
CONFIG_FILE="$REPO_ROOT/tricycle.config.yml"
STEPS="plan implement"

for arg in "$@"; do
    case "$arg" in
        --dry-run)      DRY_RUN=1 ;;
        --verbose)      VERBOSE=1 ;;
        --blocks-dir=*) BLOCKS_DIR="${arg#*=}" ;;
        --output-dir=*) OUTPUT_DIR="${arg#*=}" ;;
        --config=*)     CONFIG_FILE="${arg#*=}" ;;
        --help|-h)
            echo "Usage: assemble-commands.sh [--dry-run] [--verbose] [--blocks-dir=DIR] [--output-dir=DIR] [--config=FILE]"
            exit 0 ;;
    esac
done

# models.<key> from the config, or the default.
model_for() { # <key> <default>
    local v=""
    [[ -f "$CONFIG_FILE" ]] && v=$(awk -v k="$1" '
        /^models:/ { in_m = 1; next }
        in_m && /^[^[:space:]#]/ { in_m = 0 }
        in_m && $1 == k ":" { sub(/^[[:space:]]*[^:]+:[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); gsub(/["\047]/, ""); print; exit }
    ' "$CONFIG_FILE")
    printf '%s' "${v:-$2}"
}

step_description() {
    case "$1" in
        plan)      echo "Write or revalidate a spec (analysis, proposed solution, checklist) for a request, ticket or spec file." ;;
        implement) echo "Implement a spec that passes the validator: work its checklist, test, and ship." ;;
    esac
}

# The `enabled:` value of a top-level config section, or empty.
section_enabled() { # <section>
    [[ -f "$CONFIG_FILE" ]] || return 0
    awk -v s="$1" '
        $0 ~ "^" s ":" { in_s = 1; next }
        in_s && /^[^[:space:]#]/ { in_s = 0 }
        in_s && /^[[:space:]]+enabled:/ { sub(/^[[:space:]]+enabled:[[:space:]]*/, ""); print; exit }
    ' "$CONFIG_FILE"
}

# enable=/disable= lines for one step: feature flags first, then workflow.blocks.
step_switches() { # <step>
    local wt qa
    wt=$(section_enabled worktree); qa=$(section_enabled qa)
    if [[ "$1" == implement ]]; then
        [[ "$wt" == true ]]  && printf 'enable=worktree-setup\nenable=worktree-cleanup\n'
        [[ "$wt" == false ]] && printf 'disable=worktree-setup\ndisable=worktree-cleanup\n'
        [[ "$qa" == true ]]  && printf 'enable=qa-testing\n'
        [[ "$qa" == false ]] && printf 'disable=qa-testing\n'
    fi
    parse_block_overrides "$CONFIG_FILE" "$1"
}

# Lines ORDER|FILE|NAME|SOURCE for one step's active blocks, unsorted.
collect_blocks() { # <step>
    local step="$1" switches f name req def enabled
    switches=$(step_switches "$step")
    is_on()  { printf '%s\n' "$switches" | grep -qx "enable=$1"; }
    is_off() { printf '%s\n' "$switches" | grep -qx "disable=$1"; }

    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        name=$(get_block_field "$f" name); req=$(get_block_field "$f" required); def=$(get_block_field "$f" default_enabled)
        enabled=0
        [[ "$def" == true ]] && enabled=1
        is_on "$name" && enabled=1
        is_off "$name" && [[ "$req" != true ]] && enabled=0
        [[ $enabled -eq 1 ]] && printf '%s|%s|%s|core\n' "$(get_block_field "$f" order)" "$f" "$name"
    done < <(list_blocks_for_step "$BLOCKS_DIR" "$step")

    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        name=$(get_block_field "$f" name)
        is_on "$name" && ! is_off "$name" && printf '%s|%s|%s|optional\n' "$(get_block_field "$f" order)" "$f" "$name"
    done < <(list_blocks_for_step "$BLOCKS_DIR/optional" "$step")

    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        [[ "$f" == /* ]] || f="$REPO_ROOT/$f"
        if [[ ! -f "$f" ]]; then
            echo "ERROR: custom block not found: $f" >&2
            return 1
        fi
        printf '%s|%s|%s|custom\n' "$(get_block_field "$f" order)" "$f" "$(get_block_field "$f" name)"
    done < <(printf '%s\n' "$switches" | sed -n 's/^custom=//p')
}

assemble_step() { # <step>
    local step="$1" out="$OUTPUT_DIR/trc.$1.md" blocks
    blocks=$(collect_blocks "$step" | sort -t'|' -k1,1n)

    if [[ $VERBOSE -eq 1 || $DRY_RUN -eq 1 ]]; then
        echo "Step: $step"
        printf '%s\n' "$blocks" | while IFS='|' read -r order _ name source; do
            [[ -n "$name" ]] && echo "  $name ($source, order $order)"
        done
        echo "  → $out"
    fi
    [[ $DRY_RUN -eq 1 ]] && return 0

    local cmd_model workers validator
    case "$step" in plan) cmd_model=$(model_for plan fable) ;; *) cmd_model=$(model_for "$step" opus) ;; esac
    workers=$(model_for workers opus); validator=$(model_for validator opus)

    mkdir -p "$OUTPUT_DIR"
    {
        echo "---"
        echo "description: $(step_description "$step")"
        echo "model: $cmd_model"
        echo "---"
        echo ""
        echo "## User Input"
        echo ""
        echo '```text'
        echo '$ARGUMENTS'
        echo '```'
        echo ""
        printf '%s\n' "$blocks" | while IFS='|' read -r _ file _ _; do
            [[ -n "$file" ]] || continue
            read_block_content "$file"
            echo ""
        done
    } | sed -e "s/{{models\.workers}}/$workers/g" -e "s/{{models\.validator}}/$validator/g" > "$out.tmp.$$"
    mv -f "$out.tmp.$$" "$out"
}

for step in $STEPS; do
    assemble_step "$step"
done
[[ $DRY_RUN -eq 1 ]] || echo "Assembly complete: trc.plan.md, trc.implement.md"
