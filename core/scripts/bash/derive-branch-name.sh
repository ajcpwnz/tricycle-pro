#!/usr/bin/env bash
# derive-branch-name.sh — pure slug/branch-name derivation, no side effects.
#
# Shared by core/scripts/bash/create-new-feature.sh (branch creation) and
# core/hooks/rename-on-kickoff.sh (session label). Prints the computed
# branch name to stdout on a single line, or exits non-zero on error.
#
# NEVER creates branches, worktrees, files, or network calls. Git access
# is read-only and local-only (`git branch -a`) — no `git fetch`.
#
# See specs/TRI-31-session-rename-on-kickoff/contracts/derive-branch-name.md

set -e

JSON_MODE=false  # kept for shape parity with create-new-feature.sh flags; unused here
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
        --short-name)
            i=$((i + 1))
            [ $i -le $# ] || { echo "Error: --short-name requires a value" >&2; exit 1; }
            SHORT_NAME="${!i}"
            ;;
        --number)
            i=$((i + 1))
            [ $i -le $# ] || { echo "Error: --number requires a value" >&2; exit 1; }
            BRANCH_NUMBER="${!i}"
            ;;
        --style)
            i=$((i + 1))
            [ $i -le $# ] || { echo "Error: --style requires a value" >&2; exit 1; }
            STYLE="${!i}"
            ;;
        --issue)
            i=$((i + 1))
            [ $i -le $# ] || { echo "Error: --issue requires a value" >&2; exit 1; }
            ISSUE_ID="${!i}"
            ;;
        --prefix)
            i=$((i + 1))
            [ $i -le $# ] || { echo "Error: --prefix requires a value" >&2; exit 1; }
            ISSUE_PREFIX="${!i}"
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [--style <style>] [--short-name <slug>] [--issue <id>] [--prefix <p>] [--number N] <feature_description>

Print the branch name that would be produced for the given inputs. No side effects.

Styles: feature-name, issue-number, ordered (default: ordered)
EOF
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
    echo "Error: feature description is required" >&2
    exit 1
fi

FEATURE_DESCRIPTION=$(echo "$FEATURE_DESCRIPTION" | xargs)
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Error: feature description cannot be empty or whitespace-only" >&2
    exit 1
fi

[ -z "$STYLE" ] && STYLE="ordered"
case "$STYLE" in
    feature-name|issue-number|ordered) ;;
    *)
        echo "Error: invalid --style '$STYLE'. Must be one of: feature-name, issue-number, ordered" >&2
        exit 1
        ;;
esac

# ── Slug generation ───────────────────────────────────────────────────────

clean_branch_name() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//'
}

generate_branch_name() {
    local description="$1"
    local stop_words="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set)$"
    local clean_name
    clean_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')

    local meaningful_words=()
    for word in $clean_name; do
        [ -z "$word" ] && continue
        if ! echo "$word" | grep -qiE "$stop_words"; then
            if [ ${#word} -ge 3 ]; then
                meaningful_words+=("$word")
            elif echo "$description" | grep -q "\b${word^^}\b"; then
                meaningful_words+=("$word")
            fi
        fi
    done

    if [ ${#meaningful_words[@]} -gt 0 ]; then
        local max_words=3
        [ ${#meaningful_words[@]} -eq 4 ] && max_words=4
        local result="" count=0
        for word in "${meaningful_words[@]}"; do
            [ $count -ge $max_words ] && break
            [ -n "$result" ] && result="$result-"
            result="$result$word"
            count=$((count + 1))
        done
        echo "$result"
    else
        local cleaned
        cleaned=$(clean_branch_name "$description")
        echo "$cleaned" | tr '-' '\n' | grep -v '^$' | head -3 | tr '\n' '-' | sed 's/-$//'
    fi
}

if [ -n "$SHORT_NAME" ]; then
    BRANCH_SUFFIX=$(clean_branch_name "$SHORT_NAME")
else
    BRANCH_SUFFIX=$(generate_branch_name "$FEATURE_DESCRIPTION")
fi

# ── Ordered-style number resolution (local git only, no fetch) ────────────

get_highest_from_branches() {
    local highest=0
    local branches
    branches=$(git branch -a 2>/dev/null || echo "")
    [ -z "$branches" ] && { echo "$highest"; return; }
    while IFS= read -r branch; do
        local clean_branch number
        clean_branch=$(echo "$branch" | sed 's/^[* ]*//; s|^remotes/[^/]*/||')
        if echo "$clean_branch" | grep -q '^[0-9]\{3\}-'; then
            number=$(echo "$clean_branch" | grep -o '^[0-9]\{3\}' || echo "0")
            number=$((10#$number))
            [ "$number" -gt "$highest" ] && highest=$number
        fi
    done <<< "$branches"
    echo "$highest"
}

get_highest_from_specs() {
    local specs_dir="$1"
    local highest=0
    [ -d "$specs_dir" ] || { echo "$highest"; return; }
    local dir dirname number
    for dir in "$specs_dir"/*; do
        [ -d "$dir" ] || continue
        dirname=$(basename "$dir")
        number=$(echo "$dirname" | grep -o '^[0-9]\+' || echo "0")
        number=$((10#$number))
        [ "$number" -gt "$highest" ] && highest=$number
    done
    echo "$highest"
}

resolve_ordered_number() {
    if [ -n "$BRANCH_NUMBER" ]; then
        echo "$BRANCH_NUMBER"
        return
    fi
    local specs_dir="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/specs"
    local highest_branch highest_spec max_num
    highest_branch=$(get_highest_from_branches)
    highest_spec=$(get_highest_from_specs "$specs_dir")
    max_num=$highest_branch
    [ "$highest_spec" -gt "$max_num" ] && max_num=$highest_spec
    echo $((max_num + 1))
}

# ── Dispatch by style ─────────────────────────────────────────────────────

case "$STYLE" in
    feature-name)
        BRANCH_NAME="$BRANCH_SUFFIX"
        ;;
    issue-number)
        issue=""
        if [ -n "$ISSUE_ID" ]; then
            issue="$ISSUE_ID"
        elif [ -n "$ISSUE_PREFIX" ]; then
            issue=$(echo "$FEATURE_DESCRIPTION" | grep -ioE "${ISSUE_PREFIX}-[0-9]+" | head -1)
        else
            issue=$(echo "$FEATURE_DESCRIPTION" | grep -oE '[A-Z]+-[0-9]+' | head -1)
        fi
        if [ -z "$issue" ]; then
            echo "Error: --style issue-number requires --issue <ID> or a PREFIX-NUMBER pattern in the description" >&2
            exit 2
        fi
        issue=$(echo "$issue" | tr '[:lower:]' '[:upper:]')
        BRANCH_NAME="${issue}-${BRANCH_SUFFIX}"
        ;;
    ordered)
        number=$(resolve_ordered_number)
        feature_num=$(printf "%03d" "$((10#$number))")
        BRANCH_NAME="${feature_num}-${BRANCH_SUFFIX}"
        ;;
esac

MAX_BRANCH_LENGTH=244
if [ ${#BRANCH_NAME} -gt $MAX_BRANCH_LENGTH ]; then
    BRANCH_NAME=$(echo "$BRANCH_NAME" | cut -c1-$MAX_BRANCH_LENGTH | sed 's/-$//')
fi

printf '%s\n' "$BRANCH_NAME"
