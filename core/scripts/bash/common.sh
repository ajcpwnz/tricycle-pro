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

# Parse band.max_parallel from tricycle.config.yml.
# Returns an integer 1-8. Defaults to 3 when the file, the band: section,
# or the key is missing, or when the value is not a valid integer in range.
parse_band_config() {
    local config_file="$1"
    local default=3

    if [[ ! -f "$config_file" ]]; then
        echo "$default"
        return 0
    fi

    local in_band=0
    local value=""

    while IFS= read -r line; do
        # Detect band: section
        if [[ "$line" =~ ^band: ]]; then
            in_band=1
            continue
        fi
        # Exit band section on next top-level key
        if [[ $in_band -eq 1 ]] && [[ "$line" =~ ^[a-z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_band=0
        fi
        # Read max_parallel within band
        if [[ $in_band -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+max_parallel: ]]; then
            value=$(printf '%s' "$line" | sed 's/.*max_parallel:[[:space:]]*//' | sed 's/[[:space:]]*#.*//' | sed 's/[[:space:]]*$//')
            break
        fi
    done < "$config_file"

    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 8 )); then
        echo "$value"
    else
        echo "$default"
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

# Parse worktree provisioning config from tricycle.config.yml.
# Emits KEY=VALUE lines on stdout:
#   package_manager=<value>   (always emitted; defaults to "npm")
#   setup_script=<value>      (emitted only when set; absent => no-op)
#   env_copy=<path>           (emitted once per list item; absent => no-op)
# Callers should read line-by-line; order of keys is stable.
parse_worktree_config() {
    local config_file="$1"

    local package_manager=""
    local setup_script=""
    # env_copy items are collected as newline-separated in a single string so we
    # can print them at the end without relying on arrays (Bash 3 compatible).
    local env_copy_lines=""

    if [[ ! -f "$config_file" ]]; then
        echo "package_manager=npm"
        return 0
    fi

    local in_project=0
    local in_worktree=0
    local in_env_copy=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Top-level section detection
        if [[ "$line" =~ ^project: ]]; then
            in_project=1; in_worktree=0; in_env_copy=0; continue
        fi
        if [[ "$line" =~ ^worktree: ]]; then
            in_project=0; in_worktree=1; in_env_copy=0; continue
        fi
        if [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            in_project=0; in_worktree=0; in_env_copy=0
        fi

        if [[ $in_project -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+package_manager: ]]; then
            package_manager=$(printf '%s' "$line" | sed 's/^[[:space:]]*package_manager:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//" | sed 's/[[:space:]]*$//')
        fi

        if [[ $in_worktree -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+setup_script: ]]; then
            setup_script=$(printf '%s' "$line" | sed 's/^[[:space:]]*setup_script:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//" | sed 's/[[:space:]]*$//')
            in_env_copy=0
        fi
        if [[ $in_worktree -eq 1 ]] && [[ "$line" =~ ^[[:space:]]+env_copy: ]]; then
            # Inline form: env_copy: [a, b, c]
            local inline
            inline=$(printf '%s' "$line" | sed -n 's/.*env_copy:[[:space:]]*\[//p' | sed 's/\].*//')
            if [[ -n "$inline" ]]; then
                local item
                local IFS_BAK="$IFS"
                IFS=','
                for item in $inline; do
                    item=$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")
                    if [[ -n "$item" ]]; then
                        env_copy_lines="${env_copy_lines}${item}"$'\n'
                    fi
                done
                IFS="$IFS_BAK"
                in_env_copy=0
            else
                in_env_copy=1
                continue
            fi
        fi
        if [[ $in_env_copy -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]+- ]]; then
                local item
                item=$(printf '%s' "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//" | sed 's/[[:space:]]*$//')
                if [[ -n "$item" ]]; then
                    env_copy_lines="${env_copy_lines}${item}"$'\n'
                fi
            elif [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                in_env_copy=0
            fi
        fi
    done < "$config_file"

    if [[ -z "$package_manager" ]]; then
        echo "package_manager=npm"
    else
        echo "package_manager=$package_manager"
    fi

    if [[ -n "$setup_script" ]] && [[ "$setup_script" != "null" ]] && [[ "$setup_script" != "~" ]]; then
        echo "setup_script=$setup_script"
    fi

    if [[ -n "$env_copy_lines" ]]; then
        printf '%s' "$env_copy_lines" | while IFS= read -r item; do
            [[ -n "$item" ]] && echo "env_copy=$item"
        done
    fi
}
