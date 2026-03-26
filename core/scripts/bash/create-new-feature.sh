#!/usr/bin/env bash

set -e

JSON_MODE=false
NO_CHECKOUT=false
SHORT_NAME=""
BRANCH_NUMBER=""
STYLE=""
ISSUE_ID=""
ISSUE_PREFIX=""
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
            echo "Usage: $0 [--json] [--short-name <name>] [--number N] [--style <style>] [--issue <id>] [--prefix <prefix>] [--no-checkout] <feature_description>"
            echo ""
            echo "Options:"
            echo "  --json              Output in JSON format"
            echo "  --short-name <name> Provide a custom short name (2-4 words) for the branch"
            echo "  --number N          Specify branch number manually (overrides auto-detection, ordered style only)"
            echo "  --style <style>     Branch naming style: feature-name, issue-number, ordered (default: ordered)"
            echo "  --issue <id>        Issue identifier for issue-number style (e.g., TRI-042)"
            echo "  --prefix <prefix>   Issue prefix for extraction from description (e.g., TRI)"
            echo "  --no-checkout       Create branch without checking it out (for worktree workflows)"
            echo "  --help, -h          Show this help message"
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

if [ "$NO_CHECKOUT" = false ]; then
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
        jq -cn \
            --arg branch_name "$BRANCH_NAME" \
            --arg spec_file "$SPEC_FILE" \
            --arg feature_num "$FEATURE_NUM" \
            '{BRANCH_NAME:$branch_name,SPEC_FILE:$spec_file,FEATURE_NUM:$feature_num}'
    else
        printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s"}\n' "$(json_escape "$BRANCH_NAME")" "$(json_escape "$SPEC_FILE")" "$(json_escape "$FEATURE_NUM")"
    fi
else
    echo "BRANCH_NAME: $BRANCH_NAME"
    echo "SPEC_FILE: $SPEC_FILE"
    echo "FEATURE_NUM: $FEATURE_NUM"
    printf '# To persist in your shell: export SPECIFY_FEATURE=%q\n' "$BRANCH_NAME"
fi
