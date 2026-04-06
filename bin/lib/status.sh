#!/usr/bin/env bash
# status.sh — Feature status scanning and display

STATUS_ID=""
STATUS_NAME=""

status_detect_stage() {
  local dir_path="$1"

  if [ -f "$dir_path/tasks.md" ]; then
    local unchecked checked
    unchecked=$(grep -c '^- \[ \]' "$dir_path/tasks.md" 2>/dev/null) || unchecked=0
    checked=$(grep -cE '^- \[[xX]\]' "$dir_path/tasks.md" 2>/dev/null) || checked=0

    if [ $((unchecked + checked)) -eq 0 ]; then
      echo "tasks"
    elif [ "$unchecked" -eq 0 ]; then
      echo "done"
    elif [ "$checked" -gt 0 ]; then
      echo "implement"
    else
      echo "tasks"
    fi
    return
  fi

  if [ -f "$dir_path/plan.md" ]; then
    echo "plan"
    return
  fi

  if [ -f "$dir_path/spec.md" ]; then
    echo "specify"
    return
  fi

  echo "empty"
}

status_parse_dir_name() {
  local dir_name="$1"
  STATUS_ID=""
  STATUS_NAME=""

  # TRI-XX-slug pattern (issue-number style)
  if echo "$dir_name" | grep -qE '^[A-Z]+-[0-9]+-'; then
    STATUS_ID=$(echo "$dir_name" | sed 's/^\([A-Z]*-[0-9]*\)-.*/\1/')
    STATUS_NAME=$(echo "$dir_name" | sed 's/^[A-Z]*-[0-9]*-//')
    return
  fi

  # NNN-slug pattern (ordered style)
  if echo "$dir_name" | grep -qE '^[0-9]{3}-'; then
    STATUS_ID=$(echo "$dir_name" | sed 's/^\([0-9]*\)-.*/\1/')
    STATUS_NAME=$(echo "$dir_name" | sed 's/^[0-9]*-//')
    return
  fi

  # Fallback: full dir name
  STATUS_NAME="$dir_name"
}

status_progress_for_stage() {
  case "$1" in
    empty)     echo 0 ;;
    specify)   echo 25 ;;
    plan)      echo 50 ;;
    tasks)     echo 75 ;;
    implement) echo 80 ;;
    done)      echo 100 ;;
    *)         echo 0 ;;
  esac
}

status_render_bar() {
  local progress="$1"
  local filled=$((progress * 12 / 100))
  local empty=$((12 - filled))
  local bar=""
  local i=0
  while [ $i -lt $filled ]; do
    bar="${bar}█"
    i=$((i + 1))
  done
  i=0
  while [ $i -lt $empty ]; do
    bar="${bar}░"
    i=$((i + 1))
  done
  printf '%s' "$bar"
}

status_scan() {
  local filter="${1:-}"
  local json_mode="${2:-0}"
  local show_all="${3:-0}"
  local specs_dir="$CWD/specs"

  if [ ! -d "$specs_dir" ] || [ -z "$(ls -A "$specs_dir" 2>/dev/null)" ]; then
    if [ "$json_mode" = "1" ]; then
      echo "[]"
    else
      echo ""
      echo "  No features found. Run /trc.specify to start a new feature."
      echo ""
    fi
    return 0
  fi

  # Build list of active worktree branch names
  local worktree_branches=""
  if [ "$show_all" != "1" ] && [ -z "$filter" ]; then
    worktree_branches=$(git worktree list --porcelain 2>/dev/null | grep '^branch refs/heads/' | sed 's|^branch refs/heads/||')
  fi

  local found=0
  local json_first=1

  if [ "$json_mode" = "1" ]; then
    printf '['
  else
    echo ""
  fi

  for feature_dir in "$specs_dir"/*/; do
    [ -d "$feature_dir" ] || continue
    local dir_name
    dir_name=$(basename "$feature_dir")

    status_parse_dir_name "$dir_name"
    local id="$STATUS_ID"
    local name="$STATUS_NAME"

    # Apply filter
    if [ -n "$filter" ]; then
      if [ "$id" != "$filter" ] && [ "$dir_name" != "$filter" ]; then
        continue
      fi
    fi

    # Default: only show features with active worktrees
    if [ "$show_all" != "1" ] && [ -z "$filter" ] && [ -n "$worktree_branches" ]; then
      if ! echo "$worktree_branches" | grep -qx "$dir_name"; then
        continue
      fi
    fi

    local stage
    stage=$(status_detect_stage "$feature_dir")
    local progress
    progress=$(status_progress_for_stage "$stage")
    local bar
    bar=$(status_render_bar "$progress")

    found=$((found + 1))

    if [ "$json_mode" = "1" ]; then
      [ $json_first -eq 0 ] && printf ','
      printf '{%s, %s, %s, %s, %s}' \
        "$(json_kv "id" "${id:-$dir_name}")" \
        "$(json_kv "name" "$name")" \
        "$(json_kv "dir" "$dir_name")" \
        "$(json_kv "stage" "$stage")" \
        "$(json_kv_raw "progress" "$progress")"
      json_first=0
    else
      printf '  %-8s %-28s %s %s\n' "${id:---}" "$name" "$bar" "$stage"
    fi
  done

  if [ "$json_mode" = "1" ]; then
    printf ']\n'
  else
    if [ "$found" -eq 0 ]; then
      if [ -n "$filter" ]; then
        echo "  No feature found matching $filter"
      elif [ "$show_all" != "1" ]; then
        echo "  No active worktrees. Use --all to show all features."
      fi
    fi
    echo ""
  fi
}
