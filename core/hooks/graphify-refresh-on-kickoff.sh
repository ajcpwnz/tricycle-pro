#!/bin/bash
# UserPromptSubmit hook — optional graphify integration.
# Fires on /trc.specify, /trc.chain, and /trc.headless kickoffs and runs
# `graphify . --update` in the background so workers see a fresh graph.
#
# Every gate below is a silent early exit so downstream repos that never
# opted in (or that uninstalled graphify) feel zero impact. Only the
# fire-and-forget background spawn runs if ALL gates pass. The hook
# returns in well under 100ms regardless of repo size.
#
# See README "Graphify integration" and tricycle.config.yml
# integrations.graphify.* for config knobs.

# Dogfood bypass for this project's CI/dev dance.
if [ "$TRICYCLE_DEV" = "1" ]; then exit 0; fi

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Gate 1 — only act on kickoff commands. Mirror rename-on-kickoff.sh.
TRIMMED="${PROMPT#"${PROMPT%%[![:space:]]*}"}"
case "$TRIMMED" in
    /trc.specify*|/trc.headless*|/trc.chain*) ;;
    *) exit 0 ;;
esac

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_ROOT" ] && exit 0

# Gate 2 — config flag. Read integrations.graphify.* via a minimal YAML
# walker. Kept self-contained so the hook works in every install shape
# (no guarantee bin/lib is on PATH).
read_cfg() {
    local config="$REPO_ROOT/tricycle.config.yml"
    local section="$1" key="$2"
    [ -f "$config" ] || return 0
    awk -v s="$section" -v k="$key" '
        $0 ~ "^"s":" { in_s=1; depth=0; next }
        /^[a-zA-Z]/ && !/^[[:space:]]/ { in_s=0 }
        in_s {
            # inside graphify block — look one or two indent levels down
            if ($0 ~ "^[[:space:]]+graphify:") { in_g=1; next }
            if (in_g && $0 ~ "^[[:space:]]+"k":") {
                sub(/^[[:space:]]+[^:]+:[[:space:]]*/, "")
                gsub(/^"|"$/, "")
                gsub(/^'\''|'\''$/, "")
                sub(/[[:space:]]*#.*$/, "")
                sub(/[[:space:]]*$/, "")
                print
                exit
            }
            if (in_g && $0 ~ "^[a-zA-Z]" ) { in_g=0 }
        }
    ' "$config"
}

ENABLED=$(read_cfg integrations enabled)
[ "$ENABLED" = "true" ] || exit 0

REFRESH=$(read_cfg integrations refresh_on_kickoff)
# Default on when block is enabled.
[ "$REFRESH" = "false" ] && exit 0

AUTO_INSTALL=$(read_cfg integrations auto_install)
AUTO_BOOTSTRAP=$(read_cfg integrations auto_bootstrap)

# Gate 3 — graphify present (or auto_install permitted).
if ! command -v graphify >/dev/null 2>&1; then
    # Fall back to importable module.
    if ! python3 -c 'import graphify' >/dev/null 2>&1; then
        [ "$AUTO_INSTALL" = "true" ] || exit 0
        # auto_install path: defer to the shared CLI helper so install
        # behavior stays consistent with `tricycle graphify install`.
        # Run synchronously, then fall through to refresh — but only if
        # the install finishes fast enough; otherwise the kickoff shouldn't
        # block. We cap at 5s by backgrounding install too.
        :
    fi
fi

# Gate 4 — graph present (or auto_bootstrap permitted).
GRAPH_FILE="$REPO_ROOT/graphify-out/graph.json"
if [ ! -f "$GRAPH_FILE" ] && [ "$AUTO_BOOTSTRAP" != "true" ]; then
    exit 0
fi

# All gates passed — delegate to the CLI helper. It runs the refresh in a
# detached background process and returns immediately. The user's prompt
# is never blocked.
#
# Locate bin/tricycle. Repo-root is where the user ran from; the CLI may
# be here (tricycle-pro itself) or installed via npm (then on PATH).
TRICYCLE_BIN=""
if [ -x "$REPO_ROOT/bin/tricycle" ]; then
    TRICYCLE_BIN="$REPO_ROOT/bin/tricycle"
elif command -v tricycle >/dev/null 2>&1; then
    TRICYCLE_BIN=$(command -v tricycle)
else
    exit 0  # can't find the CLI — silently skip
fi

export TRC_GRAPHIFY_AUTO_INSTALL="$AUTO_INSTALL"
export TRC_GRAPHIFY_AUTO_BOOTSTRAP="$AUTO_BOOTSTRAP"
(cd "$REPO_ROOT" && "$TRICYCLE_BIN" graphify refresh >/dev/null 2>&1) &
disown 2>/dev/null || true
exit 0
