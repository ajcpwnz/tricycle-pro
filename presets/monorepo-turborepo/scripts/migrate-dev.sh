#!/usr/bin/env bash
# Non-interactive replacement for `prisma migrate dev`.
# Uses `prisma migrate diff` to generate SQL, then `prisma migrate deploy` to apply it.
# Usage: ./scripts/migrate-dev.sh <migration-name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BACKEND_DIR"

# --- Validate input ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <migration-name>" >&2
  echo "Example: $0 add-polst-slug" >&2
  exit 1
fi

MIGRATION_NAME="$1"

# Sanitize: lowercase, replace non-alphanumeric with underscore, collapse underscores
MIGRATION_NAME_SAFE=$(echo "$MIGRATION_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')

if [[ -z "$MIGRATION_NAME_SAFE" ]]; then
  echo "Error: migration name resolves to empty after sanitization" >&2
  exit 1
fi

# --- Ensure DATABASE_URL is set and exported ---
if [[ -z "${DATABASE_URL:-}" ]]; then
  # Try loading from .env
  if [[ -f "$BACKEND_DIR/.env" ]]; then
    DATABASE_URL=$(grep -E '^DATABASE_URL=' "$BACKEND_DIR/.env" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
  fi
  if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "Error: DATABASE_URL is not set and could not be loaded from .env" >&2
    exit 1
  fi
fi
export DATABASE_URL

# --- Check for pending schema changes ---
echo "Generating migration diff..."
# Capture only stdout (SQL); stderr (logs like "Loaded Prisma config...") goes to terminal
DIFF_SQL=$(bunx prisma migrate diff \
  --from-config-datasource \
  --to-schema prisma/schema.prisma \
  --script)

if [[ -z "$DIFF_SQL" || "$DIFF_SQL" == "-- This is an empty migration." ]]; then
  echo "No schema changes detected. Nothing to migrate."
  exit 0
fi

# --- Create migration directory ---
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
MIGRATION_DIR="prisma/migrations/${TIMESTAMP}_${MIGRATION_NAME_SAFE}"
mkdir -p "$MIGRATION_DIR"
echo "$DIFF_SQL" > "$MIGRATION_DIR/migration.sql"
echo "Created migration: $MIGRATION_DIR"
echo "SQL:"
echo "$DIFF_SQL"
echo ""

# --- Apply migration ---
echo "Applying migration..."
bunx prisma migrate deploy
echo ""

# --- Regenerate client ---
echo "Regenerating Prisma client..."
bunx prisma generate

echo ""
echo "Migration complete: $MIGRATION_DIR"
