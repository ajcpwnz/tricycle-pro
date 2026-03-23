#!/usr/bin/env bash
# Removes a git worktree and its per-branch database.
# Usage:
#   ./scripts/cleanup-worktree.sh <branch-name>       # remove one worktree
#   ./scripts/cleanup-worktree.sh --all-merged         # remove all merged worktrees
#   ./scripts/cleanup-worktree.sh --list               # list worktrees + their DBs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PG_USER="${PG_USER:-polst}"
PG_CONTAINER="${PG_CONTAINER:-backend-postgres-1}"

# --- Helpers ---

db_name_for_branch() {
  local branch="$1"
  echo "polst_$(echo "$branch" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')" | cut -c1-63
}

drop_db() {
  local db="$1"
  if docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    local exists
    exists=$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d postgres -tAc \
      "SELECT 1 FROM pg_database WHERE datname = '$db';" 2>/dev/null || echo "")
    if [[ "$exists" == "1" ]]; then
      # Terminate active connections before dropping
      docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
      docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d postgres -c "DROP DATABASE \"$db\";" 2>/dev/null
      echo "  Dropped database: $db"
    else
      echo "  Database '$db' does not exist (already clean)"
    fi
  else
    echo "  Warning: postgres container not running, skipping DB cleanup for '$db'"
  fi
}

remove_worktree() {
  local branch="$1"
  local worktree_path
  worktree_path=$(git worktree list --porcelain | grep -A2 "branch refs/heads/$branch" | head -1 | sed 's/worktree //')

  if [[ -z "$worktree_path" ]]; then
    echo "No worktree found for branch '$branch'"
    return 1
  fi

  if [[ "$worktree_path" == "$REPO_ROOT" ]]; then
    echo "Cannot remove the main worktree"
    return 1
  fi

  echo "Removing worktree: $worktree_path (branch: $branch)"

  # Drop the branch database
  local db
  db=$(db_name_for_branch "$branch")
  drop_db "$db"

  # Remove worktree
  git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path"
  echo "  Removed worktree: $worktree_path"

  # Delete the branch if it's fully merged
  if git branch --merged staging 2>/dev/null | grep -q "^\s*$branch$"; then
    git branch -d "$branch" 2>/dev/null && echo "  Deleted merged branch: $branch" || true
  else
    echo "  Branch '$branch' not merged into staging — kept"
  fi

  echo "  Done."
}

list_worktrees() {
  echo "Worktrees:"
  echo ""
  git worktree list --porcelain | while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      local path="${line#worktree }"
      local branch=""
      local bare=""
      # Read next lines for branch info
      while IFS= read -r next; do
        [[ -z "$next" ]] && break
        [[ "$next" == branch\ * ]] && branch="${next#branch refs/heads/}"
        [[ "$next" == "bare" ]] && bare="yes"
      done
      if [[ -n "$bare" ]]; then
        continue
      fi
      local db="(default: polst)"
      if [[ "$branch" != "main" && "$branch" != "staging" && -n "$branch" ]]; then
        db=$(db_name_for_branch "$branch")
      fi
      local merged=""
      if [[ "$branch" != "main" && "$branch" != "staging" && -n "$branch" ]]; then
        if git branch --merged staging 2>/dev/null | grep -q "^\s*$branch$"; then
          merged=" [MERGED]"
        fi
      fi
      printf "  %-50s %-30s db: %s%s\n" "$path" "$branch" "$db" "$merged"
    fi
  done
}

# --- Main ---

if [[ $# -lt 1 ]]; then
  echo "Usage:"
  echo "  $0 <branch-name>       Remove one worktree + its database"
  echo "  $0 --all-merged        Remove all worktrees whose branches are merged into staging"
  echo "  $0 --list              List worktrees and their databases"
  exit 1
fi

case "$1" in
  --list)
    list_worktrees
    ;;
  --all-merged)
    echo "Cleaning up merged worktrees..."
    found=0
    while IFS= read -r branch; do
      branch=$(echo "$branch" | xargs)
      [[ -z "$branch" || "$branch" == "main" || "$branch" == "staging" ]] && continue
      # Check if this branch has a worktree
      if git worktree list --porcelain | grep -q "branch refs/heads/$branch"; then
        remove_worktree "$branch"
        found=1
      fi
    done < <(git branch --merged staging 2>/dev/null)
    if [[ "$found" -eq 0 ]]; then
      echo "No merged worktrees to clean up."
    fi
    git worktree prune
    echo "Worktree list pruned."
    ;;
  *)
    remove_worktree "$1"
    git worktree prune
    ;;
esac
