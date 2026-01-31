#!/bin/bash
# =============================================================================
# Backup Script for Solution Press Automation
# =============================================================================
# Creates a complete backup of:
# - PostgreSQL database
# - n8n workflows (exported)
# - n8n data volume
# =============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_DIR}/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_${DATE}"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}

# Load environment
if [ -f "${PROJECT_DIR}/.env" ]; then
    export $(grep -v '^#' "${PROJECT_DIR}/.env" | xargs)
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}"

echo "📦 Starting backup: ${BACKUP_NAME}"

# -----------------------------------------------------------------------------
# 1. Export n8n workflows
# -----------------------------------------------------------------------------
echo "  → Exporting workflows..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T n8n \
    n8n export:workflow --all --output="/home/node/backups/${BACKUP_NAME}/workflows.json" 2>/dev/null || {
    echo "  ⚠️  Could not export workflows (n8n might be starting up)"
}

# Also export credentials (encrypted)
docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T n8n \
    n8n export:credentials --all --output="/home/node/backups/${BACKUP_NAME}/credentials.json" 2>/dev/null || {
    echo "  ⚠️  Could not export credentials"
}

# -----------------------------------------------------------------------------
# 2. Backup PostgreSQL
# -----------------------------------------------------------------------------
echo "  → Backing up database..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" -d n8n | gzip > "${BACKUP_DIR}/${BACKUP_NAME}/database.sql.gz"

# -----------------------------------------------------------------------------
# 3. Backup n8n data volume
# -----------------------------------------------------------------------------
echo "  → Backing up n8n data..."
docker run --rm \
    -v mojweb-automation_n8n_data:/data:ro \
    -v "${BACKUP_DIR}/${BACKUP_NAME}":/backup \
    alpine tar czf /backup/n8n_data.tar.gz -C /data .

# -----------------------------------------------------------------------------
# 4. Create final archive
# -----------------------------------------------------------------------------
echo "  → Creating archive..."
cd "${BACKUP_DIR}"
tar czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"
rm -rf "${BACKUP_NAME}"

# -----------------------------------------------------------------------------
# 5. Cleanup old backups
# -----------------------------------------------------------------------------
echo "  → Cleaning old backups (>${RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "backup_*.tar.gz" -mtime +${RETENTION_DAYS} -delete

# -----------------------------------------------------------------------------
# 6. Show result
# -----------------------------------------------------------------------------
BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)
echo ""
echo "✅ Backup complete!"
echo "   File: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
echo "   Size: ${BACKUP_SIZE}"
echo ""

# Optional: Upload to S3
if [ -n "${BACKUP_S3_BUCKET}" ] && [ -n "${BACKUP_S3_ACCESS_KEY}" ]; then
    echo "  → Uploading to S3..."
    # Requires rclone or aws cli configured
    # rclone copy "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" "s3:${BACKUP_S3_BUCKET}/n8n/"
    echo "  ⚠️  S3 upload not configured. Uncomment in script to enable."
fi
