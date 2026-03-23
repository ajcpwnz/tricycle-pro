#!/usr/bin/env bash
# MySQL adapter for per-worktree database isolation
# Sourced by worktree-db-setup.sh — expects these variables set:
#   DB_NAME, MYSQL_CONTAINER, MYSQL_USER, MYSQL_PASSWORD

create_db() {
  local db_name="$1"
  local container="${MYSQL_CONTAINER:-mysql}"
  local user="${MYSQL_USER:-root}"
  local password="${MYSQL_PASSWORD:-root}"

  echo "Creating database '$db_name'..."
  docker exec "$container" mysql -u "$user" -p"$password" -e \
    "CREATE DATABASE IF NOT EXISTS \`$db_name\`;" || {
    echo "Error: Failed to create database '$db_name'." >&2
    return 1
  }
  echo "Database '$db_name' created."
}

drop_db() {
  local db_name="$1"
  local container="${MYSQL_CONTAINER:-mysql}"
  local user="${MYSQL_USER:-root}"
  local password="${MYSQL_PASSWORD:-root}"

  echo "Dropping database '$db_name'..."
  docker exec "$container" mysql -u "$user" -p"$password" -e \
    "DROP DATABASE IF EXISTS \`$db_name\`;" || {
    echo "Error: Failed to drop database '$db_name'." >&2
    return 1
  }
  echo "Database '$db_name' dropped."
}

db_url() {
  local db_name="$1"
  local user="${MYSQL_USER:-root}"
  local password="${MYSQL_PASSWORD:-root}"
  local host="${MYSQL_HOST:-localhost}"
  local port="${MYSQL_PORT:-3306}"
  echo "mysql://${user}:${password}@${host}:${port}/${db_name}"
}
