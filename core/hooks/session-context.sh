#!/bin/bash
# SessionStart hook: injects constitution and configured context files into Claude's context

# Read and discard stdin (hook protocol sends session event JSON)
cat >/dev/null

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
CONF="$REPO_ROOT/.claude/hooks/.session-context.conf"

# No conf file → nothing to inject
[ -f "$CONF" ] || exit 0

# ─── Inline json_escape (from core/scripts/bash/common.sh) ──────────────────
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\b'/\\b}"
    s="${s//$'\f'/\\f}"
    s=$(printf '%s' "$s" | tr -d '\000-\007\013\016-\037')
    printf '%s' "$s"
}

# ─── Derive a label from filename ────────────────────────────────────────────
file_label() {
    local name
    name=$(basename "$1" .md)
    # Capitalize first letter (portable — works on bash 3.2+)
    local first rest
    first=$(printf '%s' "$name" | cut -c1 | tr '[:lower:]' '[:upper:]')
    rest=$(printf '%s' "$name" | cut -c2-)
    printf '%s%s' "$first" "$rest"
}

# ─── Read conf and assemble content ─────────────────────────────────────────
content=""

while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^# ]] && continue
    [ -z "$line" ] && continue

    local_path="$REPO_ROOT/$line"

    # Skip missing or empty files
    [ -f "$local_path" ] || continue
    [ -s "$local_path" ] || continue

    file_content=$(cat "$local_path")

    # Skip placeholder constitution
    if echo "$file_content" | grep -q 'Run.*trc\.constitution'; then
        continue
    fi

    label=$(file_label "$line")
    if [ -n "$content" ]; then
        content="${content}

---

"
    fi
    content="${content}## ${label} (${line})

${file_content}"
done < "$CONF"

# Nothing valid → exit silently
[ -z "$content" ] && exit 0

# Truncate at 50,000 characters
max_len=50000
if [ "${#content}" -gt "$max_len" ]; then
    content="${content:0:$max_len}

[Content truncated at 50,000 characters. Reduce context.session_start.files to stay within limit.]"
fi

# Output hook response
escaped=$(json_escape "$content")
cat <<EOJSON
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"${escaped}"}}
EOJSON
