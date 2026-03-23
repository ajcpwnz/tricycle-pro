#!/usr/bin/env bash
# Sets up a per-worktree database to avoid migration drift between branches.
# Creates a branch-specific database in the shared postgres container,
# writes DATABASE_URL to .env, and applies all existing migrations.
# Usage: cd apps/backend && ./scripts/worktree-db-setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BACKEND_DIR"

# --- Defaults (match docker-compose.yml) ---
PG_USER="${PG_USER:-polst}"
PG_PASSWORD="${PG_PASSWORD:-polst}"
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5433}"
PG_CONTAINER="${PG_CONTAINER:-backend-postgres-1}"
DEFAULT_DB="polst"

# --- Detect branch name ---
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  echo "Error: could not detect git branch. Are you in a git repository?" >&2
  exit 1
fi

# --- Determine database name ---
if [[ "$BRANCH" == "main" || "$BRANCH" == "staging" ]]; then
  DB_NAME="$DEFAULT_DB"
  echo "Branch '$BRANCH' — using default database: $DB_NAME"
else
  # Sanitize branch name: lowercase, replace non-alphanumeric with underscore
  DB_NAME="polst_$(echo "$BRANCH" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')"
  # Postgres identifiers max 63 chars
  DB_NAME="${DB_NAME:0:63}"
  echo "Branch '$BRANCH' — using worktree database: $DB_NAME"
fi

# --- Check postgres container is running ---
if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
  echo "Error: postgres container '$PG_CONTAINER' is not running." >&2
  echo "Start it with: cd apps/backend && docker compose up -d" >&2
  exit 1
fi

# --- Create database if it doesn't exist ---
DB_EXISTS=$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';" 2>/dev/null || echo "")

if [[ "$DB_EXISTS" != "1" ]]; then
  echo "Creating database '$DB_NAME'..."
  docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";"
  echo "Database created."
else
  echo "Database '$DB_NAME' already exists."
fi

# --- Copy .env from main checkout if this is a worktree with no .env ---
# Worktrees start with no .env (gitignored). Copy the full .env from the main
# checkout so all secrets (JWT, AWS, CORS, etc.) are present, then override
# DATABASE_URL for the worktree-specific database.
MAIN_CHECKOUT_ENV=""
if [[ ! -f "$BACKEND_DIR/.env" ]]; then
  # Find the main checkout's .env by walking up to the git common dir
  GIT_COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null || echo "")"
  if [[ -n "$GIT_COMMON_DIR" && "$GIT_COMMON_DIR" != "." ]]; then
    MAIN_BACKEND_ENV="$(cd "$GIT_COMMON_DIR/.." && pwd)/apps/backend/.env"
    if [[ -f "$MAIN_BACKEND_ENV" ]]; then
      cp "$MAIN_BACKEND_ENV" "$BACKEND_DIR/.env"
      MAIN_CHECKOUT_ENV="$MAIN_BACKEND_ENV"
      echo "Copied .env from main checkout ($MAIN_BACKEND_ENV)"
    fi
  fi
fi

# Also copy frontend .env if missing
FRONTEND_DIR="$(cd "$BACKEND_DIR/../frontend" 2>/dev/null && pwd || echo "")"
if [[ -n "$FRONTEND_DIR" && ! -f "$FRONTEND_DIR/.env" ]]; then
  GIT_COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null || echo "")"
  if [[ -n "$GIT_COMMON_DIR" && "$GIT_COMMON_DIR" != "." ]]; then
    MAIN_FRONTEND_ENV="$(cd "$GIT_COMMON_DIR/.." && pwd)/apps/frontend/.env"
    if [[ -f "$MAIN_FRONTEND_ENV" ]]; then
      cp "$MAIN_FRONTEND_ENV" "$FRONTEND_DIR/.env"
      echo "Copied frontend .env from main checkout ($MAIN_FRONTEND_ENV)"
    fi
  fi
fi

# --- Write DATABASE_URL to .env ---
DATABASE_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${DB_NAME}?schema=public"

if [[ -f "$BACKEND_DIR/.env" ]]; then
  # Replace existing DATABASE_URL or append
  if grep -q '^DATABASE_URL=' "$BACKEND_DIR/.env"; then
    # Use a temp file to avoid sed -i portability issues
    grep -v '^DATABASE_URL=' "$BACKEND_DIR/.env" > "$BACKEND_DIR/.env.tmp"
    echo "DATABASE_URL=\"$DATABASE_URL\"" >> "$BACKEND_DIR/.env.tmp"
    mv "$BACKEND_DIR/.env.tmp" "$BACKEND_DIR/.env"
  else
    echo "DATABASE_URL=\"$DATABASE_URL\"" >> "$BACKEND_DIR/.env"
  fi
else
  echo "DATABASE_URL=\"$DATABASE_URL\"" > "$BACKEND_DIR/.env"
fi
echo "Wrote DATABASE_URL to .env (database: $DB_NAME)"

# Export for Prisma CLI (prisma.config.ts reads process.env.DATABASE_URL)
export DATABASE_URL

# --- Apply existing migrations ---
echo "Applying migrations to '$DB_NAME'..."
bunx prisma migrate deploy
echo ""

# --- Generate Prisma client ---
echo "Generating Prisma client..."
bunx prisma generate

echo ""
echo "Worktree DB setup complete."
echo "  Database: $DB_NAME"
echo "  URL: $DATABASE_URL"
