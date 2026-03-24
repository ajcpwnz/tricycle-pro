#!/usr/bin/env bash
# yaml_parser.sh — Constrained YAML subset parser
# Converts tricycle.config.yml into flat KEY=VALUE lines
# Handles: nested objects, arrays of objects, inline JSON arrays,
#          simple value arrays, booleans, comments, quoted strings

parse_yaml() {
  local file="$1"
  [ -f "$file" ] || return 1

  awk '
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*#/ { next }
  {
    # Count leading spaces
    indent = 0
    tmp = $0
    while (substr(tmp, 1, 1) == " ") { indent++; tmp = substr(tmp, 2) }
    depth = int(indent / 2)
    line = tmp

    # Clear key stack entries at or beyond current depth
    for (d = depth; d <= 20; d++) {
      if (d in key_at) delete key_at[d]
    }

    # Check for array item "- "
    is_arr = 0
    if (substr(line, 1, 2) == "- ") {
      is_arr = 1
      line = substr(line, 3)

      # Build parent path up to depth-1
      parent = ""
      for (d = 0; d < depth; d++) {
        if (d in key_at) {
          if (parent != "") parent = parent "."
          parent = parent key_at[d]
        }
      }

      # Increment array counter for this parent
      if (!(parent in arr_idx)) arr_idx[parent] = 0
      else arr_idx[parent]++

      key_at[depth] = arr_idx[parent]
      depth = depth + 1
    }

    # Find first colon
    colon = index(line, ":")
    if (colon > 0) {
      k = substr(line, 1, colon - 1)
      rest = substr(line, colon + 1)
      # Trim leading/trailing whitespace from rest
      gsub(/^[[:space:]]+/, "", rest)
      gsub(/[[:space:]]+$/, "", rest)

      if (rest == "") {
        # Parent key (no value) — push onto stack
        key_at[depth] = k
      } else {
        # Build full path
        path = ""
        for (d = 0; d < depth; d++) {
          if (d in key_at) {
            if (path != "") path = path "."
            path = path key_at[d]
          }
        }
        if (path != "") path = path "."
        path = path k

        # Check for inline JSON array ["a", "b"]
        if (substr(rest, 1, 1) == "[" && substr(rest, length(rest), 1) == "]") {
          inner = substr(rest, 2, length(rest) - 2)
          n = split(inner, items, ",")
          for (i = 1; i <= n; i++) {
            v = items[i]
            gsub(/^[[:space:]]*"?/, "", v)
            gsub(/"?[[:space:]]*$/, "", v)
            print path "." (i - 1) "=" v
          }
        } else {
          # Strip surrounding quotes
          if (substr(rest, 1, 1) == "\"" && substr(rest, length(rest), 1) == "\"") {
            rest = substr(rest, 2, length(rest) - 2)
          }
          print path "=" rest
        }
      }
    } else if (is_arr && line != "") {
      # Bare value in a simple array (no colon)
      path = ""
      for (d = 0; d < depth; d++) {
        if (d in key_at) {
          if (path != "") path = path "."
          path = path key_at[d]
        }
      }
      # Strip quotes
      if (substr(line, 1, 1) == "\"" && substr(line, length(line), 1) == "\"") {
        line = substr(line, 2, length(line) - 2)
      }
      print path "=" line
    }
  }
  ' "$file"
}
