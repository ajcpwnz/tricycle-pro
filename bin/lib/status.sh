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
    active)    echo 0 ;;
    stale)     echo 100 ;;
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

status_emit_entry() {
  local id="$1" name="$2" dir_name="$3" stage="$4" json_mode="$5" json_first="$6"
  local progress bar
  progress=$(status_progress_for_stage "$stage")
  bar=$(status_render_bar "$progress")

  if [ "$json_mode" = "1" ]; then
    [ "$json_first" = "0" ] && printf ','
    printf '{%s, %s, %s, %s, %s}' \
      "$(json_kv "id" "${id:-$dir_name}")" \
      "$(json_kv "name" "$name")" \
      "$(json_kv "dir" "$dir_name")" \
      "$(json_kv "stage" "$stage")" \
      "$(json_kv_raw "progress" "$progress")"
  else
    printf '  %-8s %-28s %s %s\n' "${id:---}" "$name" "$bar" "$stage"
  fi
}

# Scan worktrees and show status for each (default mode).
# Excludes the main worktree and common base branches.
status_scan_worktrees() {
  local filter="${1:-}"
  local json_mode="${2:-0}"
  local specs_dir="$CWD/specs"
  local found=0
  local json_first=1

  if [ "$json_mode" = "1" ]; then
    printf '['
  else
    echo ""
  fi

  # Read base branch from config to exclude it from worktree list
  local base_branch="main"
  if [ -f "$CWD/tricycle.config.yml" ]; then
    local parsed
    parsed=$(grep -E '^\s+base_branch:' "$CWD/tricycle.config.yml" 2>/dev/null | head -1 | sed 's/.*base_branch:[[:space:]]*//' | tr -d '"'"'" | tr -d '[:space:]')
    [ -n "$parsed" ] && base_branch="$parsed"
  fi

  # Get merged PR branch names in one gh call (handles squash merges)
  local merged_branches=""
  if command -v gh >/dev/null 2>&1; then
    merged_branches=$(gh pr list --state merged --json headRefName --jq '.[].headRefName' --limit 200 2>/dev/null || true)
  fi

  local worktree_path="" worktree_branch=""
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      # End of worktree block — process if we have a feature branch
      if [ -n "$worktree_branch" ] && [ "$worktree_branch" != "$base_branch" ] && [ "$worktree_branch" != "staging" ] && [ "$worktree_branch" != "main" ] && [ "$worktree_branch" != "master" ]; then
        status_parse_dir_name "$worktree_branch"
        local id="$STATUS_ID"
        local name="$STATUS_NAME"

        # Apply filter
        local skip=0
        if [ -n "$filter" ]; then
          if [ "$id" != "$filter" ] && [ "$worktree_branch" != "$filter" ]; then
            skip=1
          fi
        fi

        if [ "$skip" = "0" ]; then
          # Check if branch PR was merged (handles squash merges)
          local is_merged=0
          if [ -n "$merged_branches" ] && echo "$merged_branches" | grep -qx "$worktree_branch"; then
            is_merged=1
          fi

          local stage="active"
          if [ "$is_merged" = "1" ]; then
            stage="stale"
          elif [ -d "$specs_dir/$worktree_branch" ]; then
            stage=$(status_detect_stage "$specs_dir/$worktree_branch")
          fi

          status_emit_entry "$id" "$name" "$worktree_branch" "$stage" "$json_mode" "$json_first"
          [ "$json_mode" = "1" ] && json_first=0
          found=$((found + 1))
        fi
      fi
      worktree_path=""
      worktree_branch=""
      continue
    fi
    case "$line" in
      worktree\ *) worktree_path="${line#worktree }" ;;
      branch\ *)   worktree_branch="${line#branch refs/heads/}" ;;
    esac
  done <<EOF
$(git worktree list --porcelain 2>/dev/null)

EOF

  if [ "$json_mode" = "1" ]; then
    printf ']\n'
  else
    if [ "$found" -eq 0 ]; then
      if [ -n "$filter" ]; then
        echo "  No worktree found matching $filter"
      else
        echo "  No active worktrees. Use --all to show all features."
      fi
    fi
    echo ""
  fi
}

# Scan all spec directories (--all mode).
status_scan_all() {
  local filter="${1:-}"
  local json_mode="${2:-0}"
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

    if [ -n "$filter" ]; then
      if [ "$id" != "$filter" ] && [ "$dir_name" != "$filter" ]; then
        continue
      fi
    fi

    local stage
    stage=$(status_detect_stage "$feature_dir")

    status_emit_entry "$id" "$name" "$dir_name" "$stage" "$json_mode" "$json_first"
    [ "$json_mode" = "1" ] && json_first=0
    found=$((found + 1))
  done

  if [ "$json_mode" = "1" ]; then
    printf ']\n'
  else
    if [ "$found" -eq 0 ] && [ -n "$filter" ]; then
      echo "  No feature found matching $filter"
    fi
    echo ""
  fi
}

status_scan() {
  local filter="${1:-}"
  local json_mode="${2:-0}"
  local show_all="${3:-0}"

  if [ "$show_all" = "1" ] || [ -n "$filter" ]; then
    status_scan_all "$filter" "$json_mode"
  else
    status_scan_worktrees "$filter" "$json_mode"
  fi
}
