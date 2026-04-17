#!/usr/bin/env bash

# Exit codes reserved for the --provision-worktree pipeline (see TRI-26):
#   10 = .trc/ copy into worktree failed
#   11 = package-manager install failed (or binary not on PATH)
#   12 = worktree.setup_script path does not exist in worktree root
#   13 = worktree.setup_script is not executable
#   14 = worktree.setup_script exited non-zero
#   15 = one or more worktree.env_copy paths missing after setup
# Exit codes reserved for the base-branch refresh step (see TRI-32):
#   20 = dirty working tree on base branch (cannot fast-forward safely)
#   21 = local base diverged from origin or non-fast-forward
# These codes must not be reused for anything else.

set -e

JSON_MODE=false
NO_CHECKOUT=false
PROVISION_WORKTREE=false
SKIP_BASE_REFRESH=false
SHORT_NAME=""
BRANCH_NUMBER=""
STYLE=""
ISSUE_ID=""
ISSUE_PREFIX=""
PACKAGE_MANAGER="npm"
SETUP_SCRIPT=""
ENV_COPY_ITEMS=""  # newline-separated
ARGS=()

# Honor the env-var opt-out (FR-011). The --no-base-refresh flag below sets
# the same variable for the command-line path.
if [ "${TRC_SKIP_BASE_REFRESH:-}" = "1" ]; then
    SKIP_BASE_REFRESH=true
fi
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
        --no-base-refresh)
            SKIP_BASE_REFRESH=true
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
            echo "Usage: $0 [--json] [--short-name <name>] [--number N] [--style <style>] [--issue <id>] [--prefix <prefix>] [--no-checkout] [--provision-worktree] [--no-base-refresh] <feature_description>"
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
            echo "  --no-base-refresh     Skip the automatic 'git fetch + fast-forward' of the configured base"
            echo "                        branch before creating the new branch. Equivalent to TRC_SKIP_BASE_REFRESH=1."
            echo "                        Useful when deliberately branching off a historical SHA. See TRI-32."
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

# --- Delegate slug + branch-name derivation to the shared helper ---
# derive-branch-name.sh is the single source of truth for slug generation
# and style dispatch (see TRI-31 FR-007). Keeping a shared helper means a
# future change to branching rules propagates to both branch creation here
# and session-label derivation in .claude/hooks/rename-on-kickoff.sh.

DERIVE_SH="$SCRIPT_DIR/derive-branch-name.sh"
if [ ! -x "$DERIVE_SH" ]; then
    >&2 echo "Error: derive-branch-name.sh not found or not executable at $DERIVE_SH"
    exit 1
fi

DERIVE_ARGS=(--style "$STYLE")
[ -n "$SHORT_NAME" ]     && DERIVE_ARGS+=(--short-name "$SHORT_NAME")
[ -n "$BRANCH_NUMBER" ]  && DERIVE_ARGS+=(--number "$BRANCH_NUMBER")
[ -n "$ISSUE_ID" ]       && DERIVE_ARGS+=(--issue "$ISSUE_ID")
[ -n "$ISSUE_PREFIX" ]   && DERIVE_ARGS+=(--prefix "$ISSUE_PREFIX")

set +e
BRANCH_NAME=$(REPO_ROOT="$REPO_ROOT" bash "$DERIVE_SH" "${DERIVE_ARGS[@]}" "$FEATURE_DESCRIPTION" 2>/tmp/.derive_err_$$)
DERIVE_RC=$?
set -e
if [ $DERIVE_RC -ne 0 ]; then
    # Propagate the helper's stderr and exit code so callers see the same
    # "Issue number required…" kind of message they had before.
    cat /tmp/.derive_err_$$ >&2 2>/dev/null || true
    rm -f /tmp/.derive_err_$$
    exit $DERIVE_RC
fi
rm -f /tmp/.derive_err_$$

# Derive FEATURE_NUM from the computed branch name + style, preserving
# the JSON contract that downstream templates and tests depend on.
case "$STYLE" in
    feature-name)
        FEATURE_NUM=""
        ;;
    issue-number)
        # BRANCH_NAME = "${ISSUE}-${SUFFIX}" where ISSUE matches [A-Z0-9]+-[0-9]+.
        FEATURE_NUM=$(echo "$BRANCH_NAME" | grep -oE '^[A-Z][A-Z0-9]*-[0-9]+' | head -1)
        ;;
    ordered)
        FEATURE_NUM=$(echo "$BRANCH_NAME" | grep -oE '^[0-9]{3}' | head -1)
        # Keep BRANCH_NUMBER in sync for any downstream code that reads it.
        BRANCH_NUMBER=$((10#$FEATURE_NUM))
        ;;
esac

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

# Read push.pr_target from tricycle.config.yml. Mirrors read_project_name.
# Prints empty on absence; callers default to "main".
read_pr_target() {
    local config_file="$1"
    [ -f "$config_file" ] || return 0
    awk '
        /^push:/ { in_p=1; next }
        /^[a-zA-Z]/ && !/^[[:space:]]/ { in_p=0 }
        in_p && /^[[:space:]]+pr_target:/ {
            sub(/^[[:space:]]+pr_target:[[:space:]]*/, "")
            gsub(/^"|"$/, "")
            gsub(/^'\''|'\''$/, "")
            sub(/[[:space:]]*$/, "")
            print
            exit
        }
    ' "$config_file"
}

# refresh_base_branch REPO_ROOT BASE_BRANCH
# Fast-forward local <base> from origin before a new feature branch is cut.
# See specs/TRI-32-pull-fresh-base/contracts/refresh-base-branch.md.
#
# Exit codes used inside (propagated via exit on halt):
#   20 = dirty working tree on base branch
#   21 = divergent local base (non-fast-forward)
# Otherwise returns 0, including for all graceful-skip paths.
refresh_base_branch() {
    local repo_root="$1"
    local base="$2"

    # Opt-out: flag or env var (FR-011).
    if [ "$SKIP_BASE_REFRESH" = "true" ]; then
        return 0
    fi

    # Not-a-git-repo → silent no-op (FR-007).
    if [ "${HAS_GIT:-false}" != "true" ]; then
        return 0
    fi

    # Reachability probe. On network-class failures: warn, skip (FR-006).
    local probe_err
    probe_err=$(git -C "$repo_root" fetch --dry-run origin "$base" 2>&1) || {
        case "$probe_err" in
            *"Could not resolve host"*|*"Connection refused"*|*"Operation timed out"*|\
            *"unable to access"*|*"Authentication failed"*|*"Network is unreachable"*|\
            *"Could not read from remote"*|*"timed out"*)
                >&2 echo "[specify] Warning: origin unreachable; skipping base-branch refresh. New branch will be cut from local ${base}."
                return 0
                ;;
            *)
                # Real fetch error (missing ref, auth/perm problem on a valid
                # remote, server-side rejection). Surface and halt — do NOT
                # silently proceed with stale local state.
                >&2 echo "Error: git fetch origin ${base} failed:"
                >&2 echo "$probe_err"
                exit 21
                ;;
        esac
    }

    local current_branch sha_before sha_after
    current_branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    sha_before=$(git -C "$repo_root" rev-parse --verify -q "$base" 2>/dev/null || echo "")

    if [ "$current_branch" = "$base" ]; then
        # On base — dirty-tree guard then ff-only pull (FR-003, FR-004).
        if ! git -C "$repo_root" diff-index --quiet HEAD -- 2>/dev/null \
             || ! git -C "$repo_root" diff-files --quiet 2>/dev/null; then
            >&2 echo "Error: Working tree on ${base} has uncommitted changes. Commit, stash, or discard them and retry."
            >&2 echo "Dirty paths:"
            git -C "$repo_root" status --porcelain=v1 2>/dev/null | sed 's/^/  /' >&2
            exit 20
        fi
        local pull_err
        pull_err=$(git -C "$repo_root" pull --ff-only origin "$base" 2>&1) || {
            >&2 echo "Error: local ${base} cannot fast-forward from origin/${base} (diverged or non-FF). Resolve manually and retry."
            >&2 echo "$pull_err"
            exit 21
        }
    else
        # Off base — direct ref update, no HEAD switch (FR-008).
        local fetch_err
        fetch_err=$(git -C "$repo_root" fetch origin "${base}:${base}" 2>&1) || {
            >&2 echo "Error: local ${base} cannot fast-forward from origin/${base} (diverged or non-FF). Resolve manually and retry."
            >&2 echo "$fetch_err"
            exit 21
        }
    fi

    sha_after=$(git -C "$repo_root" rev-parse --verify -q "$base" 2>/dev/null || echo "")
    if [ -n "$sha_after" ] && [ "$sha_before" != "$sha_after" ]; then
        >&2 echo "[specify] Base branch ${base} fast-forwarded to ${sha_after:0:12}"
    fi
    return 0
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

# TRI-32: fast-forward local base before cutting the new branch so every
# kickoff (specify/headless/chain worker) starts from fresh upstream state.
# This runs AFTER the helper-function definitions above and BEFORE branch
# creation below — placement enforced by bash's top-to-bottom parse.
if [ "$HAS_GIT" = true ]; then
    BASE_BRANCH=$(read_pr_target "$REPO_ROOT/tricycle.config.yml")
    [ -z "$BASE_BRANCH" ] && BASE_BRANCH="main"
    refresh_base_branch "$REPO_ROOT" "$BASE_BRANCH"
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
