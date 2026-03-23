#!/usr/bin/env bash
# SQLite adapter for per-worktree database isolation
# Simplest option — each worktree gets its own .sqlite file

create_db() {
  local db_name="$1"
  local db_dir="${SQLITE_DIR:-.}"
  local db_path="${db_dir}/${db_name}.sqlite"

  if [[ -f "$db_path" ]]; then
    echo "Database '$db_path' already exists."
    return 0
  fi

  echo "Creating database '$db_path'..."
  touch "$db_path" || {
    echo "Error: Failed to create database '$db_path'." >&2
    return 1
  }
  echo "Database '$db_path' created."
}

drop_db() {
  local db_name="$1"
  local db_dir="${SQLITE_DIR:-.}"
  local db_path="${db_dir}/${db_name}.sqlite"

  if [[ -f "$db_path" ]]; then
    echo "Removing database '$db_path'..."
    rm -f "$db_path"
    echo "Database '$db_path' removed."
  fi
}

db_url() {
  local db_name="$1"
  local db_dir="${SQLITE_DIR:-.}"
  echo "file:${db_dir}/${db_name}.sqlite"
}
