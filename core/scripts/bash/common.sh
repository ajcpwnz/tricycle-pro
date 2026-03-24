#!/usr/bin/env bash
# Common functions and variables for all scripts

# Get repository root, with fallback for non-git repositories
get_repo_root() {
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
    else
        # Fall back to script location for non-git repos
        local script_dir="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        (cd "$script_dir/../../.." && pwd)
    fi
}

# Get current branch, with fallback for non-git repositories
get_current_branch() {
    # First check if SPECIFY_FEATURE environment variable is set
    if [[ -n "${SPECIFY_FEATURE:-}" ]]; then
        echo "$SPECIFY_FEATURE"
        return
    fi

    # Then check git if available
    if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
        git rev-parse --abbrev-ref HEAD
        return
    fi

    # For non-git repos, try to find the latest feature directory
    local repo_root=$(get_repo_root)
    local specs_dir="$repo_root/specs"

    if [[ -d "$specs_dir" ]]; then
        local latest_feature=""
        local highest=0

        for dir in "$specs_dir"/*; do
            if [[ -d "$dir" ]]; then
                local dirname=$(basename "$dir")
                if [[ "$dirname" =~ ^([0-9]{3})- ]]; then
                    local number=${BASH_REMATCH[1]}
                    number=$((10#$number))
                    if [[ "$number" -gt "$highest" ]]; then
                        highest=$number
                        latest_feature=$dirname
                    fi
                fi
            fi
        done

        if [[ -n "$latest_feature" ]]; then
            echo "$latest_feature"
            return
        fi
    fi

    echo "main"  # Final fallback
}

# Check if we have git available
has_git() {
    git rev-parse --show-toplevel >/dev/null 2>&1
}

check_feature_branch() {
    local branch="$1"
    local has_git_repo="$2"

    # For non-git repos, we can't enforce branch naming but still provide output
    if [[ "$has_git_repo" != "true" ]]; then
        echo "[specify] Warning: Git repository not detected; skipped branch validation" >&2
        return 0
    fi

    if [[ ! "$branch" =~ ^[0-9]{3}- ]]; then
        echo "ERROR: Not on a feature branch. Current branch: $branch" >&2
        echo "Feature branches should be named like: 001-feature-name" >&2
        return 1
    fi

    return 0
}

get_feature_dir() { echo "$1/specs/$2"; }

# Find feature directory by numeric prefix instead of exact branch match
# This allows multiple branches to work on the same spec (e.g., 004-fix-bug, 004-add-feature)
find_feature_dir_by_prefix() {
    local repo_root="$1"
    local branch_name="$2"
    local specs_dir="$repo_root/specs"

    # Extract numeric prefix from branch (e.g., "004" from "004-whatever")
    if [[ ! "$branch_name" =~ ^([0-9]{3})- ]]; then
        # If branch doesn't have numeric prefix, fall back to exact match
        echo "$specs_dir/$branch_name"
        return
    fi

    local prefix="${BASH_REMATCH[1]}"

    # Search for directories in specs/ that start with this prefix
    local matches=()
    if [[ -d "$specs_dir" ]]; then
        for dir in "$specs_dir"/"$prefix"-*; do
            if [[ -d "$dir" ]]; then
                matches+=("$(basename "$dir")")
            fi
        done
    fi

    # Handle results
    if [[ ${#matches[@]} -eq 0 ]]; then
        # No match found - return the branch name path (will fail later with clear error)
        echo "$specs_dir/$branch_name"
    elif [[ ${#matches[@]} -eq 1 ]]; then
        # Exactly one match - perfect!
        echo "$specs_dir/${matches[0]}"
    else
        # Multiple matches - this shouldn't happen with proper naming convention
        echo "ERROR: Multiple spec directories found with prefix '$prefix': ${matches[*]}" >&2
        echo "Please ensure only one spec directory exists per numeric prefix." >&2
        return 1
    fi
}

get_feature_paths() {
    local repo_root=$(get_repo_root)
    local current_branch=$(get_current_branch)
    local has_git_repo="false"

    if has_git; then
        has_git_repo="true"
    fi

    # Use prefix-based lookup to support multiple branches per spec
    local feature_dir
    if ! feature_dir=$(find_feature_dir_by_prefix "$repo_root" "$current_branch"); then
        echo "ERROR: Failed to resolve feature directory" >&2
        return 1
    fi

    # Use printf '%q' to safely quote values, preventing shell injection
    # via crafted branch names or paths containing special characters
    printf 'REPO_ROOT=%q\n' "$repo_root"
    printf 'CURRENT_BRANCH=%q\n' "$current_branch"
    printf 'HAS_GIT=%q\n' "$has_git_repo"
    printf 'FEATURE_DIR=%q\n' "$feature_dir"
    printf 'FEATURE_SPEC=%q\n' "$feature_dir/spec.md"
    printf 'IMPL_PLAN=%q\n' "$feature_dir/plan.md"
    printf 'TASKS=%q\n' "$feature_dir/tasks.md"
    printf 'RESEARCH=%q\n' "$feature_dir/research.md"
    printf 'DATA_MODEL=%q\n' "$feature_dir/data-model.md"
    printf 'QUICKSTART=%q\n' "$feature_dir/quickstart.md"
    printf 'CONTRACTS_DIR=%q\n' "$feature_dir/contracts"
}

# Check if jq is available for safe JSON construction
has_jq() {
    command -v jq >/dev/null 2>&1
}

# Escape a string for safe embedding in a JSON value (fallback when jq is unavailable).
# Handles backslash, double-quote, and JSON-required control character escapes (RFC 8259).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\b'/\\b}"
    s="${s//$'\f'/\\f}"
    # Strip remaining control characters (U+0000–U+001F) not individually escaped above
    s=$(printf '%s' "$s" | tr -d '\000-\007\013\016-\037')
    printf '%s' "$s"
}

# ─── Block Frontmatter Parsing ────────────────────────────────────────────

# Parse YAML frontmatter from a block file.
# Reads between the opening and closing --- markers.
# Outputs KEY=VALUE pairs (name, step, description, required, default_enabled, order).
parse_block_frontmatter() {
    local file="$1"
    local in_frontmatter=0
    local passed_first_marker=0

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if [[ $passed_first_marker -eq 0 ]]; then
                passed_first_marker=1
                in_frontmatter=1
                continue
            else
                break
            fi
        fi
        if [[ $in_frontmatter -eq 1 ]]; then
            # Parse key: value (simple flat YAML)
            local key value
            key=$(printf '%s' "$line" | sed -n 's/^\([a-z_]*\):.*/\1/p')
            value=$(printf '%s' "$line" | sed -n 's/^[a-z_]*:[[:space:]]*//p' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            if [[ -n "$key" ]]; then
                printf '%s=%s\n' "$key" "$value"
            fi
        fi
    done < "$file"
}

# List all .md block files in a step's block directory, sorted by name.
list_blocks_for_step() {
    local blocks_dir="$1"
    local step="$2"
    local step_dir="$blocks_dir/$step"

    if [[ -d "$step_dir" ]]; then
        find "$step_dir" -maxdepth 1 -name '*.md' -type f | sort
    fi
}

# Extract body content from a block file (everything below the closing --- frontmatter marker).
read_block_content() {
    local file="$1"
    local passed_markers=0

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            passed_markers=$((passed_markers + 1))
            if [[ $passed_markers -eq 2 ]]; then
                # Read remaining content
                cat
                break
            fi
            continue
        fi
    done < "$file"
}

# Get a specific frontmatter field value from a block file.
get_block_field() {
    local file="$1"
    local field="$2"
    parse_block_frontmatter "$file" | grep "^${field}=" | head -1 | cut -d= -f2-
}

# ─── Workflow Chain Config Parsing ────────────────────────────────────────

# Parse workflow.chain from tricycle.config.yml.
# Returns space-separated step names (e.g., "specify plan tasks implement").
# Defaults to full chain if not configured.
parse_chain_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        echo "specify plan tasks implement"
        return 0
    fi

    # Look for workflow.chain as a YAML list
    local in_workflow=0
    local in_chain=0
    local chain_items=""

    while IFS= read -r line; do
        # Detect workflow: section
        if [[ "$line" =~ ^workflow: ]]; then
            in_workflow=1
            continue
        fi
        # Exit workflow section on next top-level key
        if [[ $in_workflow -eq 1 ]] && [[ "$line" =~ ^[a-z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_workflow=0
            in_chain=0
        fi
        # Detect chain: within workflow
        if [[ $in_workflow -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+chain: ]]; then
            # Check for inline list: chain: [specify, plan, implement]
            local inline
            inline=$(printf '%s' "$line" | sed -n 's/.*chain:[[:space:]]*\[//p' | sed 's/\].*//')
            if [[ -n "$inline" ]]; then
                printf '%s' "$inline" | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr '\n' ' ' | sed 's/[[:space:]]*$//'
                echo
                return 0
            fi
            in_chain=1
            continue
        fi
        # Read chain list items (- specify, - plan, etc.)
        if [[ $in_chain -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]+- ]]; then
                local item
                item=$(printf '%s' "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*$//')
                chain_items="${chain_items}${chain_items:+ }${item}"
            else
                # End of chain list
                in_chain=0
            fi
        fi
    done < "$config_file"

    if [[ -n "$chain_items" ]]; then
        echo "$chain_items"
    else
        echo "specify plan tasks implement"
    fi
}

# Parse block overrides for a specific step from tricycle.config.yml.
# Outputs lines like: disable=block-name, enable=block-name, custom=path
parse_block_overrides() {
    local config_file="$1"
    local step="$2"

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    local in_workflow=0
    local in_blocks=0
    local in_step=0
    local in_section=""
    local _bo_item=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^workflow: ]]; then in_workflow=1; continue; fi
        if [[ $in_workflow -eq 1 ]] && [[ "$line" =~ ^[a-z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_workflow=0; in_blocks=0; in_step=0
        fi
        if [[ $in_workflow -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+blocks: ]]; then in_blocks=1; continue; fi
        if [[ $in_blocks -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{4}${step}: ]]; then in_step=1; continue; fi
        if [[ $in_step -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{4}[a-z] ]] && [[ ! "$line" =~ ^[[:space:]]{4}${step}: ]]; then
            in_step=0
        fi
        if [[ $in_step -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]+(disable|enable|custom): ]]; then
                in_section=$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | sed 's/:.*//')
                continue
            fi
            if [[ -n "$in_section" ]] && [[ "$line" =~ ^[[:space:]]+- ]]; then
                _bo_item=$(printf '%s' "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*$//')
                printf '%s=%s\n' "$in_section" "$_bo_item"
            fi
        fi
    done < "$config_file"
}

# Validate a chain configuration. Returns 0 if valid, 1 with error message if invalid.
validate_chain() {
    local chain="$1"  # space-separated step names

    # Convert to array
    local steps=()
    read -ra steps <<< "$chain"

    # Must start with specify
    if [[ "${steps[0]}" != "specify" ]]; then
        echo "ERROR: Chain must start with 'specify'. Got: ${steps[0]}" >&2
        return 1
    fi

    # Must end with implement
    if [[ "${steps[${#steps[@]}-1]}" != "implement" ]]; then
        echo "ERROR: Chain must end with 'implement'. Got: ${steps[${#steps[@]}-1]}" >&2
        return 1
    fi

    # Check valid variants
    local chain_str="${steps[*]}"
    case "$chain_str" in
        "specify plan tasks implement"|"specify plan implement"|"specify implement")
            return 0
            ;;
        *)
            echo "ERROR: Invalid chain '${chain_str}'. Valid chains: [specify, plan, tasks, implement], [specify, plan, implement], [specify, implement]" >&2
            return 1
            ;;
    esac
}

check_file() { [[ -f "$1" ]] && echo "  ✓ $2" || echo "  ✗ $2"; }
check_dir() { [[ -d "$1" && -n $(ls -A "$1" 2>/dev/null) ]] && echo "  ✓ $2" || echo "  ✗ $2"; }

# Resolve a template name to a file path using the priority stack:
#   1. .specify/templates/overrides/
#   2. .specify/presets/<preset-id>/templates/ (sorted by priority from .registry)
#   3. .specify/extensions/<ext-id>/templates/
#   4. .specify/templates/ (core)
resolve_template() {
    local template_name="$1"
    local repo_root="$2"
    local base="$repo_root/.specify/templates"

    # Priority 1: Project overrides
    local override="$base/overrides/${template_name}.md"
    [ -f "$override" ] && echo "$override" && return 0

    # Priority 2: Installed presets (sorted by priority from .registry)
    local presets_dir="$repo_root/.specify/presets"
    if [ -d "$presets_dir" ]; then
        local registry_file="$presets_dir/.registry"
        if [ -f "$registry_file" ] && command -v python3 >/dev/null 2>&1; then
            # Read preset IDs sorted by priority (lower number = higher precedence).
            # The python3 call is wrapped in an if-condition so that set -e does not
            # abort the function when python3 exits non-zero (e.g. invalid JSON).
            local sorted_presets=""
            if sorted_presets=$(TRICYCLE_REGISTRY="$registry_file" python3 -c "
import json, sys, os
try:
    with open(os.environ['TRICYCLE_REGISTRY']) as f:
        data = json.load(f)
    presets = data.get('presets', {})
    for pid, meta in sorted(presets.items(), key=lambda x: x[1].get('priority', 10)):
        print(pid)
except Exception:
    sys.exit(1)
" 2>/dev/null); then
                if [ -n "$sorted_presets" ]; then
                    # python3 succeeded and returned preset IDs — search in priority order
                    while IFS= read -r preset_id; do
                        local candidate="$presets_dir/$preset_id/templates/${template_name}.md"
                        [ -f "$candidate" ] && echo "$candidate" && return 0
                    done <<< "$sorted_presets"
                fi
                # python3 succeeded but registry has no presets — nothing to search
            else
                # python3 failed (missing, or registry parse error) — fall back to unordered directory scan
                for preset in "$presets_dir"/*/; do
                    [ -d "$preset" ] || continue
                    local candidate="$preset/templates/${template_name}.md"
                    [ -f "$candidate" ] && echo "$candidate" && return 0
                done
            fi
        else
            # Fallback: alphabetical directory order (no python3 available)
            for preset in "$presets_dir"/*/; do
                [ -d "$preset" ] || continue
                local candidate="$preset/templates/${template_name}.md"
                [ -f "$candidate" ] && echo "$candidate" && return 0
            done
        fi
    fi

    # Priority 3: Extension-provided templates
    local ext_dir="$repo_root/.specify/extensions"
    if [ -d "$ext_dir" ]; then
        for ext in "$ext_dir"/*/; do
            [ -d "$ext" ] || continue
            # Skip hidden directories (e.g. .backup, .cache)
            case "$(basename "$ext")" in .*) continue;; esac
            local candidate="$ext/templates/${template_name}.md"
            [ -f "$candidate" ] && echo "$candidate" && return 0
        done
    fi

    # Priority 4: Core templates
    local core="$base/${template_name}.md"
    [ -f "$core" ] && echo "$core" && return 0

    # Template not found in any location.
    # Return 1 so callers can distinguish "not found" from "found".
    # Callers running under set -e should use: TEMPLATE=$(resolve_template ...) || true
    return 1
}
