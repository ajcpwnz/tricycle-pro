#!/bin/bash
# UserPromptSubmit hook (TRI-31): rename the current Claude Code session to
# match the branch/worktree name whenever the user kicks off /trc.specify,
# /trc.headless, or /trc.chain. Fires before the agent sees the prompt, so
# the "first thing done" rule (FR-001) is satisfied structurally.
#
# Emits {"hookSpecificOutput": {"sessionTitle": "<label>"}} on match.
# Emits empty stdout on no-match or on any derivation failure (the command
# templates carry a /rename fallback for those cases).
#
# See specs/TRI-31-session-rename-on-kickoff/contracts/derive-branch-name.md.

# Dogfood bypass for this project's CI/dev dance.
if [ "$TRICYCLE_DEV" = "1" ]; then exit 0; fi

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Strip leading whitespace; only act on kickoff commands.
TRIMMED="${PROMPT#"${PROMPT%%[![:space:]]*}"}"
case "$TRIMMED" in
    /trc.specify*|/trc.headless*|/trc.chain*) ;;
    *) exit 0 ;;
esac

COMMAND="${TRIMMED%%[[:space:]]*}"
ARGSTR="${TRIMMED#"$COMMAND"}"
ARGSTR="${ARGSTR#"${ARGSTR%%[![:space:]]*}"}"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && exit 0

# Minimal YAML read for branching.style and branching.prefix. We avoid
# sourcing bin/lib/yaml_parser.sh because hooks run without the bin/ on
# PATH in every install and this single-purpose read keeps the hook
# self-contained.
read_branching() {
    local config="$REPO_ROOT/tricycle.config.yml"
    local key="$1"
    [ -f "$config" ] || return 0
    awk -v k="$key" '
        /^branching:/ { in_b=1; next }
        /^[a-zA-Z]/ && !/^[[:space:]]/ { in_b=0 }
        in_b && $0 ~ "^[[:space:]]+"k":" {
            sub(/^[[:space:]]+[^:]+:[[:space:]]*/, "")
            gsub(/^"|"$/, "")
            gsub(/^'\''|'\''$/, "")
            sub(/[[:space:]]*$/, "")
            print
            exit
        }
    ' "$config"
}

emit() {
    local title="$1"
    [ -z "$title" ] && exit 0
    # Idempotency: host may expose the current label via $CLAUDE_SESSION_TITLE.
    # If it matches, emit nothing — no "(2)" suffix, no double-rename.
    if [ -n "${CLAUDE_SESSION_TITLE:-}" ] && [ "$CLAUDE_SESSION_TITLE" = "$title" ]; then
        exit 0
    fi
    # jq -c keeps the output on one line and escapes the value correctly.
    printf '%s' "$title" | jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", sessionTitle:.}}' 2>/dev/null
    exit 0
}

derive_chain_label() {
    local arg="$1"
    [ -z "$arg" ] && return 0

    # Normalize separators: arrow (→, ->), comma, and whitespace all act as
    # token delimiters. Keep `..` (range) intact for the range branch below.
    local normalized
    normalized=$(printf '%s' "$arg" \
        | sed 's/→/ /g; s/->/ /g; s/,/ /g' \
        | awk '{$1=$1; print}')
    [ -z "$normalized" ] && return 0

    # Range form: first token contains `..` → trc-chain-LEFT..RIGHT
    local first_token
    first_token=$(printf '%s' "$normalized" | awk '{print $1}')
    if printf '%s' "$first_token" | grep -q '\.\.'; then
        local left right
        left="${first_token%%..*}"
        right="${first_token##*..}"
        if [ -n "$left" ] && [ -n "$right" ]; then
            printf 'trc-chain-%s..%s' "$left" "$right"
            return 0
        fi
    fi

    # List or singleton: count whitespace-separated tokens → first+(N-1)
    local count first
    count=$(printf '%s' "$normalized" | awk '{print NF}')
    first="$first_token"
    [ -z "$first" ] && return 0
    [ -z "$count" ] && count=1
    printf 'trc-chain-%s+%d' "$first" "$((count - 1))"
}

derive_feature_label() {
    local arg="$1"
    [ -z "$arg" ] && return 0

    local style prefix
    style=$(read_branching style)
    prefix=$(read_branching prefix)
    [ -z "$style" ] && style="feature-name"

    local derive="$REPO_ROOT/core/scripts/bash/derive-branch-name.sh"
    # Consumer installs land the script under .trc/scripts/bash/.
    [ -x "$derive" ] || derive="$REPO_ROOT/.trc/scripts/bash/derive-branch-name.sh"
    [ -x "$derive" ] || return 0

    # Strip any PREFIX-NUMBER token from the description before deriving
    # the slug so the issue ID doesn't get absorbed into the slug itself
    # (which would produce labels like "TRI-200-tri-200-dark").
    local description="$arg"
    description=$(printf '%s' "$description" | sed -E 's/[A-Za-z][A-Za-z0-9]*-[0-9]+//g' | awk '{$1=$1}1')
    [ -z "$description" ] && description="$arg"

    local derive_args=(--style "$style")
    case "$style" in
        issue-number)
            local issue=""
            if [ -n "$prefix" ]; then
                issue=$(printf '%s' "$arg" | grep -ioE "${prefix}-[0-9]+" | head -1)
            else
                issue=$(printf '%s' "$arg" | grep -oE '[A-Z]+-[0-9]+' | head -1)
            fi
            # No ticket yet — defer to the command-template fallback, which
            # runs after the agent has prompted the user for one.
            [ -z "$issue" ] && return 0
            derive_args+=(--issue "$issue")
            [ -n "$prefix" ] && derive_args+=(--prefix "$prefix")
            ;;
    esac

    REPO_ROOT="$REPO_ROOT" bash "$derive" "${derive_args[@]}" "$description" 2>/dev/null
}

case "$COMMAND" in
    /trc.chain)
        LABEL=$(derive_chain_label "$ARGSTR")
        ;;
    /trc.specify|/trc.headless)
        LABEL=$(derive_feature_label "$ARGSTR")
        ;;
esac

emit "$LABEL"
