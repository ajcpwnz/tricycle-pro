#!/usr/bin/env bash

# Exit codes reserved for the --provision-worktree pipeline (see TRI-26):
#   10 = .trc/ copy into worktree failed
#   11 = package-manager install failed (or binary not on PATH)
#   12 = worktree.setup_script path does not exist in worktree root
#   13 = worktree.setup_script is not executable
#   14 = worktree.setup_script exited non-zero
#   15 = one or more worktree.env_copy paths missing after setup
# These codes must not be reused for anything else.

set -e

JSON_MODE=false
NO_CHECKOUT=false
PROVISION_WORKTREE=false
SHORT_NAME=""
BRANCH_NUMBER=""
STYLE=""
ISSUE_ID=""
ISSUE_PREFIX=""
PACKAGE_MANAGER="npm"
SETUP_SCRIPT=""
ENV_COPY_ITEMS=""  # newline-separated
ARGS=()
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --no-checkout)
            NO_CHECKOUT=true
            ;;
        --provision-worktree)
            PROVISION_WORKTREE=true
            NO_CHECKOUT=true  # provisioning owns worktree creation; main checkout stays put
            ;;
        --short-name)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --short-name requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            # Check if the next argument is another option (starts with --)
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --short-name requires a value' >&2
                exit 1
            fi
            SHORT_NAME="$next_arg"
            ;;
        --number)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --number requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --number requires a value' >&2
                exit 1
            fi
            BRANCH_NUMBER="$next_arg"
            ;;
        --style)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --style requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --style requires a value' >&2
                exit 1
            fi
            STYLE="$next_arg"
            ;;
        --issue)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --issue requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --issue requires a value' >&2
                exit 1
            fi
            ISSUE_ID="$next_arg"
            ;;
        --prefix)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --prefix requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --prefix requires a value' >&2
                exit 1
            fi
            ISSUE_PREFIX="$next_arg"
            ;;
        --help|-h)
            echo "Usage: $0 [--json] [--short-name <name>] [--number N] [--style <style>] [--issue <id>] [--prefix <prefix>] [--no-checkout] [--provision-worktree] <feature_description>"
            echo ""
            echo "Options:"
            echo "  --json                Output in JSON format"
            echo "  --short-name <name>   Provide a custom short name (2-4 words) for the branch"
            echo "  --number N            Specify branch number manually (overrides auto-detection, ordered style only)"
            echo "  --style <style>       Branch naming style: feature-name, issue-number, ordered (default: ordered)"
            echo "  --issue <id>          Issue identifier for issue-number style (e.g., TRI-042)"
            echo "  --prefix <prefix>     Issue prefix for extraction from description (e.g., TRI)"
            echo "  --no-checkout         Create branch without checking it out (for worktree workflows)"
            echo "  --provision-worktree  Create worktree, copy .trc/, install deps, run worktree.setup_script, and"
            echo "                        verify worktree.env_copy paths (implies --no-checkout). See TRI-26."
            echo "  --help, -h            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 'Add dark mode toggle' --style feature-name --short-name 'dark-mode'"
            echo "  $0 'TRI-042 Add export to CSV' --style issue-number --prefix TRI --short-name 'export-csv'"
            echo "  $0 'Add user authentication' --style ordered --short-name 'user-auth'"
            echo "  $0 'Add user authentication' --short-name 'user-auth'  # defaults to ordered"
            exit 0
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
    i=$((i + 1))
done

FEATURE_DESCRIPTION="${ARGS[*]}"
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Usage: $0 [--json] [--short-name <name>] [--number N] <feature_description>" >&2
    exit 1
fi

# Trim whitespace and validate description is not empty (e.g., user passed only whitespace)
FEATURE_DESCRIPTION=$(echo "$FEATURE_DESCRIPTION" | xargs)
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Error: Feature description cannot be empty or contain only whitespace" >&2
    exit 1
fi

# Validate and default the style
if [ -z "$STYLE" ]; then
    STYLE="ordered"
fi
case "$STYLE" in
    feature-name|issue-number|ordered) ;;
    *)
        echo "Error: Invalid --style '$STYLE'. Must be one of: feature-name, issue-number, ordered" >&2
        exit 1
        ;;
esac

# Function to find the repository root by searching for existing project markers
find_repo_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -d "$dir/.trc" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Function to get highest number from specs directory
get_highest_from_specs() {
    local specs_dir="$1"
    local highest=0

    if [ -d "$specs_dir" ]; then
        for dir in "$specs_dir"/*; do
            [ -d "$dir" ] || continue
            dirname=$(basename "$dir")
            number=$(echo "$dirname" | grep -o '^[0-9]\+' || echo "0")
            number=$((10#$number))
            if [ "$number" -gt "$highest" ]; then
                highest=$number
            fi
        done
    fi

    echo "$highest"
}

# Function to get highest number from git branches
get_highest_from_branches() {
    local highest=0

    # Get all branches (local and remote)
    branches=$(git branch -a 2>/dev/null || echo "")

    if [ -n "$branches" ]; then
        while IFS= read -r branch; do
            # Clean branch name: remove leading markers and remote prefixes
            clean_branch=$(echo "$branch" | sed 's/^[* ]*//; s|^remotes/[^/]*/||')

            # Extract feature number if branch matches pattern ###-*
            if echo "$clean_branch" | grep -q '^[0-9]\{3\}-'; then
                number=$(echo "$clean_branch" | grep -o '^[0-9]\{3\}' || echo "0")
                number=$((10#$number))
                if [ "$number" -gt "$highest" ]; then
                    highest=$number
                fi
            fi
        done <<< "$branches"
    fi

    echo "$highest"
}

# Function to check existing branches (local and remote) and return next available number
check_existing_branches() {
    local specs_dir="$1"

    # Fetch all remotes to get latest branch info (suppress errors if no remotes)
    git fetch --all --prune >/dev/null 2>&1 || true

    # Get highest number from ALL branches (not just matching short name)
    local highest_branch=$(get_highest_from_branches)

    # Get highest number from ALL specs (not just matching short name)
    local highest_spec=$(get_highest_from_specs "$specs_dir")

    # Take the maximum of both
    local max_num=$highest_branch
    if [ "$highest_spec" -gt "$max_num" ]; then
        max_num=$highest_spec
    fi

    # Return next number
    echo $((max_num + 1))
}

# Function to clean and format a branch name
clean_branch_name() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//'
}

# Resolve repository root. Prefer git information when available, but fall back
# to searching for repository markers so the workflow still functions in repositories that
# were initialised with --no-git.
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT=$(git rev-parse --show-toplevel)
    HAS_GIT=true
else
    REPO_ROOT="$(find_repo_root "$SCRIPT_DIR")"
    if [ -z "$REPO_ROOT" ]; then
        echo "Error: Could not determine repository root. Please run this script from within the repository." >&2
        exit 1
    fi
    HAS_GIT=false
fi

cd "$REPO_ROOT"

SPECS_DIR="$REPO_ROOT/specs"
mkdir -p "$SPECS_DIR"

# Function to generate branch name with stop word filtering and length filtering
generate_branch_name() {
    local description="$1"

    # Common stop words to filter out
    local stop_words="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set)$"

    # Convert to lowercase and split into words
    local clean_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')

    # Filter words: remove stop words and words shorter than 3 chars (unless they're uppercase acronyms in original)
    local meaningful_words=()
    for word in $clean_name; do
        # Skip empty words
        [ -z "$word" ] && continue

        # Keep words that are NOT stop words AND (length >= 3 OR are potential acronyms)
        if ! echo "$word" | grep -qiE "$stop_words"; then
            if [ ${#word} -ge 3 ]; then
                meaningful_words+=("$word")
            elif echo "$description" | grep -q "\b${word^^}\b"; then
                # Keep short words if they appear as uppercase in original (likely acronyms)
                meaningful_words+=("$word")
            fi
        fi
    done

    # If we have meaningful words, use first 3-4 of them
    if [ ${#meaningful_words[@]} -gt 0 ]; then
        local max_words=3
        if [ ${#meaningful_words[@]} -eq 4 ]; then max_words=4; fi

        local result=""
        local count=0
        for word in "${meaningful_words[@]}"; do
            if [ $count -ge $max_words ]; then break; fi
            if [ -n "$result" ]; then result="$result-"; fi
            result="$result$word"
            count=$((count + 1))
        done
        echo "$result"
    else
        # Fallback to original logic if no meaningful words found
        local cleaned=$(clean_branch_name "$description")
        echo "$cleaned" | tr '-' '\n' | grep -v '^$' | head -3 | tr '\n' '-' | sed 's/-$//'
    fi
}

# Generate branch suffix (slug) from short name or description
if [ -n "$SHORT_NAME" ]; then
    BRANCH_SUFFIX=$(clean_branch_name "$SHORT_NAME")
else
    BRANCH_SUFFIX=$(generate_branch_name "$FEATURE_DESCRIPTION")
fi

# --- Style-aware branch name generation ---

generate_ordered_branch() {
    if [ -z "$BRANCH_NUMBER" ]; then
        if [ "$HAS_GIT" = true ]; then
            BRANCH_NUMBER=$(check_existing_branches "$SPECS_DIR")
        else
            local highest
            highest=$(get_highest_from_specs "$SPECS_DIR")
            BRANCH_NUMBER=$((highest + 1))
        fi
    fi
    FEATURE_NUM=$(printf "%03d" "$((10#$BRANCH_NUMBER))")
    BRANCH_NAME="${FEATURE_NUM}-${BRANCH_SUFFIX}"
}

generate_feature_name_branch() {
    FEATURE_NUM=""
    BRANCH_NAME="$BRANCH_SUFFIX"
}

generate_issue_number_branch() {
    local issue=""
    if [ -n "$ISSUE_ID" ]; then
        issue="$ISSUE_ID"
    elif [ -n "$ISSUE_PREFIX" ]; then
        issue=$(echo "$FEATURE_DESCRIPTION" | grep -ioE "${ISSUE_PREFIX}-[0-9]+" | head -1)
    else
        issue=$(echo "$FEATURE_DESCRIPTION" | grep -oE '[A-Z]+-[0-9]+' | head -1)
    fi
    if [ -z "$issue" ]; then
        echo "Error: Issue number required for issue-number style. Use --issue <ID> or include it in the description (e.g., TRI-042)." >&2
        exit 2
    fi
    # Normalize issue to uppercase
    issue=$(echo "$issue" | tr '[:lower:]' '[:upper:]')
    FEATURE_NUM="$issue"
    BRANCH_NAME="${issue}-${BRANCH_SUFFIX}"
}

# Dispatch by style
case "$STYLE" in
    feature-name) generate_feature_name_branch ;;
    issue-number) generate_issue_number_branch ;;
    ordered)      generate_ordered_branch ;;
esac

# GitHub enforces a 244-byte limit on branch names
MAX_BRANCH_LENGTH=244
if [ ${#BRANCH_NAME} -gt $MAX_BRANCH_LENGTH ]; then
    ORIGINAL_BRANCH_NAME="$BRANCH_NAME"
    BRANCH_NAME=$(echo "$BRANCH_NAME" | cut -c1-$MAX_BRANCH_LENGTH | sed 's/-$//')
    >&2 echo "[specify] Warning: Branch name exceeded GitHub's 244-byte limit"
    >&2 echo "[specify] Original: $ORIGINAL_BRANCH_NAME (${#ORIGINAL_BRANCH_NAME} bytes)"
    >&2 echo "[specify] Truncated to: $BRANCH_NAME (${#BRANCH_NAME} bytes)"
fi

# Read project.name from tricycle.config.yml (needed for worktree path).
# Minimal single-purpose parse; only used when PROVISION_WORKTREE=true.
read_project_name() {
    local config_file="$1"
    [ -f "$config_file" ] || return 0
    awk '
        /^project:/ { in_p=1; next }
        /^[a-zA-Z]/ && !/^[[:space:]]/ { in_p=0 }
        in_p && /^[[:space:]]+name:/ {
            sub(/^[[:space:]]+name:[[:space:]]*/, "")
            gsub(/^"|"$/, "")
            gsub(/^'\''|'\''$/, "")
            sub(/[[:space:]]*$/, "")
            print
            exit
        }
    ' "$config_file"
}

# Full --provision-worktree pipeline. Reserved exit codes 10-15 (see header).
# Arguments:
#   $1 = worktree absolute path
#   $2 = main checkout .trc/ absolute path
#   $3 = package_manager
#   $4 = setup_script (may be empty)
#   $5 = env_copy newline-separated list (may be empty)
provision_worktree() {
    local worktree_path="$1"
    local main_trc_source="$2"
    local pkg_mgr="$3"
    local setup_script="$4"
    local env_copy="$5"

    # Step 1: copy .trc/ into the worktree (idempotent).
    if [ ! -e "$worktree_path/.trc" ]; then
        if ! cp -R "$main_trc_source" "$worktree_path/.trc" 2>/tmp/.trc_cp_err_$$; then
            local reason
            reason=$(cat /tmp/.trc_cp_err_$$ 2>/dev/null || true)
            rm -f /tmp/.trc_cp_err_$$
            >&2 echo "Error: failed to copy .trc/ into worktree at $worktree_path: ${reason:-unknown reason}"
            exit 10
        fi
        rm -f /tmp/.trc_cp_err_$$
    fi

    # Step 2: package-manager install.
    if ! command -v "$pkg_mgr" >/dev/null 2>&1; then
        >&2 echo "Error: package manager '$pkg_mgr' not found on PATH"
        exit 11
    fi
    local install_rc=0
    set +e
    ( cd "$worktree_path" && "$pkg_mgr" install </dev/null )
    install_rc=$?
    set -e
    if [ "$install_rc" -ne 0 ]; then
        >&2 echo "Error: '$pkg_mgr install' failed with exit $install_rc in $worktree_path"
        exit 11
    fi

    # Step 3: worktree.setup_script, if set.
    if [ -n "$setup_script" ]; then
        local script_abs="$worktree_path/$setup_script"
        if [ ! -e "$script_abs" ]; then
            >&2 echo "Error: worktree.setup_script '$setup_script' does not exist in worktree root"
            exit 12
        fi
        if [ ! -x "$script_abs" ]; then
            >&2 echo "Error: worktree.setup_script '$setup_script' is not executable"
            exit 13
        fi
        local script_rc=0
        set +e
        ( cd "$worktree_path" && "./$setup_script" </dev/null )
        script_rc=$?
        set -e
        if [ "$script_rc" -ne 0 ]; then
            >&2 echo "Error: worktree.setup_script '$setup_script' exited $script_rc"
            exit 14
        fi
    fi

    # Step 4: verify every env_copy path exists under worktree root.
    if [ -n "$env_copy" ]; then
        local missing=""
        local item
        printf '%s' "$env_copy" | while IFS= read -r item; do
            [ -z "$item" ] && continue
            if [ ! -e "$worktree_path/$item" ]; then
                printf '%s\n' "$item"
            fi
        done > /tmp/.trc_missing_$$
        missing=$(cat /tmp/.trc_missing_$$)
        rm -f /tmp/.trc_missing_$$
        if [ -n "$missing" ]; then
            >&2 echo "Error: worktree.env_copy paths missing after setup:"
            printf '%s\n' "$missing" | while IFS= read -r item; do
                [ -z "$item" ] && continue
                >&2 echo "  - $item"
            done
            exit 15
        fi
    fi
}

if [ "$HAS_GIT" = true ]; then
    if [ "$NO_CHECKOUT" = true ]; then
        if ! git branch "$BRANCH_NAME" 2>/dev/null; then
            if git branch --list "$BRANCH_NAME" | grep -q .; then
                >&2 echo "Error: Branch '$BRANCH_NAME' already exists. Please use a different feature name or specify a different number with --number."
                exit 1
            else
                >&2 echo "Error: Failed to create git branch '$BRANCH_NAME'. Please check your git configuration and try again."
                exit 1
            fi
        fi
    else
        if ! git checkout -b "$BRANCH_NAME" 2>/dev/null; then
            if git branch --list "$BRANCH_NAME" | grep -q .; then
                >&2 echo "Error: Branch '$BRANCH_NAME' already exists. Please use a different feature name or specify a different number with --number."
                exit 1
            else
                >&2 echo "Error: Failed to create git branch '$BRANCH_NAME'. Please check your git configuration and try again."
                exit 1
            fi
        fi
    fi
else
    >&2 echo "[specify] Warning: Git repository not detected; skipped branch creation for $BRANCH_NAME"
fi

FEATURE_DIR="$SPECS_DIR/$BRANCH_NAME"
SPEC_FILE="$FEATURE_DIR/spec.md"
WORKTREE_PATH=""

if [ "$PROVISION_WORKTREE" = true ]; then
    if [ "$HAS_GIT" != true ]; then
        >&2 echo "Error: --provision-worktree requires a git repository"
        exit 1
    fi

    # Parse provisioning config from tricycle.config.yml
    CONFIG_FILE="$REPO_ROOT/tricycle.config.yml"
    PROJECT_NAME=$(read_project_name "$CONFIG_FILE")
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME=$(basename "$REPO_ROOT")
    fi

    # Collect provisioning config
    ENV_COPY_LINES=""
    while IFS= read -r cfg_line; do
        case "$cfg_line" in
            package_manager=*) PACKAGE_MANAGER="${cfg_line#package_manager=}" ;;
            setup_script=*)    SETUP_SCRIPT="${cfg_line#setup_script=}" ;;
            env_copy=*)        ENV_COPY_LINES="${ENV_COPY_LINES}${cfg_line#env_copy=}"$'\n' ;;
        esac
    done < <(parse_worktree_config "$CONFIG_FILE")

    # Compute worktree path: ../{project.name}-{BRANCH_NAME}
    REPO_PARENT=$(dirname "$REPO_ROOT")
    WORKTREE_PATH="$REPO_PARENT/${PROJECT_NAME}-${BRANCH_NAME}"

    if [ -e "$WORKTREE_PATH" ]; then
        >&2 echo "Error: worktree path '$WORKTREE_PATH' already exists"
        exit 1
    fi

    if ! git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" >/dev/null 2>&1; then
        >&2 echo "Error: 'git worktree add $WORKTREE_PATH $BRANCH_NAME' failed"
        exit 1
    fi

    provision_worktree "$WORKTREE_PATH" "$REPO_ROOT/.trc" "$PACKAGE_MANAGER" "$SETUP_SCRIPT" "$ENV_COPY_LINES"

    # Create spec dir and copy template INSIDE the worktree
    FEATURE_DIR="$WORKTREE_PATH/specs/$BRANCH_NAME"
    SPEC_FILE="$FEATURE_DIR/spec.md"
    mkdir -p "$FEATURE_DIR"
    TEMPLATE=$(resolve_template "spec-template" "$REPO_ROOT") || true
    if [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ]; then
        cp "$TEMPLATE" "$SPEC_FILE"
    else
        echo "Warning: Spec template not found; created empty spec file" >&2
        touch "$SPEC_FILE"
    fi
elif [ "$NO_CHECKOUT" = false ]; then
    mkdir -p "$FEATURE_DIR"

    TEMPLATE=$(resolve_template "spec-template" "$REPO_ROOT") || true
    if [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ]; then
        cp "$TEMPLATE" "$SPEC_FILE"
    else
        echo "Warning: Spec template not found; created empty spec file" >&2
        touch "$SPEC_FILE"
    fi
fi

# Inform the user how to persist the feature variable in their own shell
printf '# To persist: export SPECIFY_FEATURE=%q\n' "$BRANCH_NAME" >&2

if $JSON_MODE; then
    if command -v jq >/dev/null 2>&1; then
        if [ "$PROVISION_WORKTREE" = true ]; then
            jq -cn \
                --arg branch_name "$BRANCH_NAME" \
                --arg spec_file "$SPEC_FILE" \
                --arg feature_num "$FEATURE_NUM" \
                --arg worktree_path "$WORKTREE_PATH" \
                '{BRANCH_NAME:$branch_name,SPEC_FILE:$spec_file,FEATURE_NUM:$feature_num,WORKTREE_PATH:$worktree_path}'
        else
            jq -cn \
                --arg branch_name "$BRANCH_NAME" \
                --arg spec_file "$SPEC_FILE" \
                --arg feature_num "$FEATURE_NUM" \
                '{BRANCH_NAME:$branch_name,SPEC_FILE:$spec_file,FEATURE_NUM:$feature_num}'
        fi
    else
        if [ "$PROVISION_WORKTREE" = true ]; then
            printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s","WORKTREE_PATH":"%s"}\n' \
                "$(json_escape "$BRANCH_NAME")" "$(json_escape "$SPEC_FILE")" "$(json_escape "$FEATURE_NUM")" "$(json_escape "$WORKTREE_PATH")"
        else
            printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s"}\n' \
                "$(json_escape "$BRANCH_NAME")" "$(json_escape "$SPEC_FILE")" "$(json_escape "$FEATURE_NUM")"
        fi
    fi
else
    echo "BRANCH_NAME: $BRANCH_NAME"
    echo "SPEC_FILE: $SPEC_FILE"
    echo "FEATURE_NUM: $FEATURE_NUM"
    if [ "$PROVISION_WORKTREE" = true ]; then
        echo "WORKTREE_PATH: $WORKTREE_PATH"
    fi
    printf '# To persist in your shell: export SPECIFY_FEATURE=%q\n' "$BRANCH_NAME"
fi
