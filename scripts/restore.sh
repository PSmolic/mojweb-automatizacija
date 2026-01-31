#!/bin/bash
# =============================================================================
# Restore Script for Solution Press Automation
# =============================================================================
# Usage: ./restore.sh backup_20260126_120000.tar.gz
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_DIR}/backups"

# Load environment
if [[ -f "${PROJECT_DIR}/.env" ]]; then
    set -a
    source "${PROJECT_DIR}/.env"
    set +a
fi

# Check arguments
if [ -z "$1" ]; then
    echo "❌ Error: Please specify backup file"
    echo "   Usage: ./restore.sh backup_20260126_120000.tar.gz"
    echo ""
    echo "Available backups:"
    ls -la "${BACKUP_DIR}"/*.tar.gz 2>/dev/null || echo "   No backups found."
    exit 1
fi

BACKUP_FILE="$1"

# Check if file exists
if [ ! -f "${BACKUP_DIR}/${BACKUP_FILE}" ] && [ ! -f "${BACKUP_FILE}" ]; then
    echo "❌ Error: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

# Use full path
if [ -f "${BACKUP_FILE}" ]; then
    BACKUP_PATH="${BACKUP_FILE}"
else
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
fi

echo "⚠️  WARNING: This will overwrite all current data!"
echo "   Backup: ${BACKUP_PATH}"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo ""
echo "📦 Starting restore..."

# -----------------------------------------------------------------------------
# 1. Extract backup
# -----------------------------------------------------------------------------
echo "  → Extracting backup..."
tar xzf "${BACKUP_PATH}" -C "${TEMP_DIR}"
BACKUP_NAME=$(ls "${TEMP_DIR}")

# -----------------------------------------------------------------------------
# 2. Stop services
# -----------------------------------------------------------------------------
echo "  → Stopping services..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" down

# -----------------------------------------------------------------------------
# 3. Restore PostgreSQL
# -----------------------------------------------------------------------------
echo "  → Restoring database..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d postgres
sleep 5  # Wait for postgres to start

# Drop and recreate database
docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T postgres \
    psql -U "${POSTGRES_USER}" -c "DROP DATABASE IF EXISTS n8n;"
docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T postgres \
    psql -U "${POSTGRES_USER}" -c "CREATE DATABASE n8n;"

# Restore data
gunzip -c "${TEMP_DIR}/${BACKUP_NAME}/database.sql.gz" | \
    docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d n8n

# -----------------------------------------------------------------------------
# 4. Restore n8n data volume
# -----------------------------------------------------------------------------
echo "  → Restoring n8n data..."
docker run --rm \
    -v mojweb-automation_n8n_data:/data \
    -v "${TEMP_DIR}/${BACKUP_NAME}":/backup \
    alpine sh -c "rm -rf /data/* && tar xzf /backup/n8n_data.tar.gz -C /data"

# -----------------------------------------------------------------------------
# 5. Start services
# -----------------------------------------------------------------------------
echo "  → Starting services..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d

# Wait for n8n to be ready
echo "  → Waiting for n8n to start..."
sleep 10

# -----------------------------------------------------------------------------
# 6. Import workflows (if available)
# -----------------------------------------------------------------------------
if [ -f "${TEMP_DIR}/${BACKUP_NAME}/workflows.json" ]; then
    echo "  → Importing workflows..."
    docker cp "${TEMP_DIR}/${BACKUP_NAME}/workflows.json" \
        $(docker compose -f "${PROJECT_DIR}/docker-compose.yml" ps -q n8n):/tmp/workflows.json
    docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T n8n \
        n8n import:workflow --input=/tmp/workflows.json || {
        echo "  ⚠️  Workflow import failed (they may already exist from data restore)"
    }
fi

echo ""
echo "✅ Restore complete!"
echo "   Access n8n at: https://${N8N_HOST}"
