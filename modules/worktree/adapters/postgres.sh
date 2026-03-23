#!/usr/bin/env bash
# Postgres adapter for per-worktree database isolation
# Sourced by worktree-db-setup.sh — expects these variables set:
#   DB_NAME, PG_CONTAINER, PG_USER, PG_DEFAULT_DB

create_db() {
  local db_name="$1"
  local container="${PG_CONTAINER:-postgres}"
  local user="${PG_USER:-postgres}"
  local default_db="${PG_DEFAULT_DB:-postgres}"

  # Check if database exists
  local exists
  exists=$(docker exec "$container" psql -U "$user" -d "$default_db" -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '$db_name';" 2>/dev/null)

  if [[ "$exists" == "1" ]]; then
    echo "Database '$db_name' already exists."
    return 0
  fi

  echo "Creating database '$db_name'..."
  docker exec "$container" psql -U "$user" -d "$default_db" -c \
    "CREATE DATABASE \"$db_name\";" || {
    echo "Error: Failed to create database '$db_name'." >&2
    return 1
  }
  echo "Database '$db_name' created."
}

drop_db() {
  local db_name="$1"
  local container="${PG_CONTAINER:-postgres}"
  local user="${PG_USER:-postgres}"
  local default_db="${PG_DEFAULT_DB:-postgres}"

  echo "Terminating connections to '$db_name'..."
  docker exec "$container" psql -U "$user" -d "$default_db" -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db_name' AND pid <> pg_backend_pid();" \
    2>/dev/null

  echo "Dropping database '$db_name'..."
  docker exec "$container" psql -U "$user" -d "$default_db" -c \
    "DROP DATABASE IF EXISTS \"$db_name\";" || {
    echo "Error: Failed to drop database '$db_name'." >&2
    return 1
  }
  echo "Database '$db_name' dropped."
}

db_url() {
  local db_name="$1"
  local user="${PG_USER:-postgres}"
  local password="${PG_PASSWORD:-postgres}"
  local host="${PG_HOST:-localhost}"
  local port="${PG_PORT:-5432}"
  echo "postgresql://${user}:${password}@${host}:${port}/${db_name}"
}
