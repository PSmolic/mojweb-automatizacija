#!/bin/bash
# =============================================================================
# Import Workflows Script
# =============================================================================
# Imports workflows from ./workflows/ into n8n
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="${PROJECT_DIR}/workflows"

echo "📥 Importing workflows..."

# Check if main export file exists
if [ -f "${WORKFLOWS_DIR}/all_workflows.json" ]; then
    echo "  → Importing from all_workflows.json..."
    
    docker cp "${WORKFLOWS_DIR}/all_workflows.json" \
        $(docker compose -f "${PROJECT_DIR}/docker-compose.yml" ps -q n8n):/tmp/import_workflows.json
    
    docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T n8n \
        n8n import:workflow --input=/tmp/import_workflows.json
    
    echo "✅ Workflows imported successfully!"
else
    # Import individual JSON files
    echo "  → Looking for individual workflow files..."
    
    find "${WORKFLOWS_DIR}" -name "*.json" -type f | while read -r file; do
        echo "  → Importing: $(basename "$file")"
        
        docker cp "$file" \
            $(docker compose -f "${PROJECT_DIR}/docker-compose.yml" ps -q n8n):/tmp/workflow.json
        
        docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T n8n \
            n8n import:workflow --input=/tmp/workflow.json 2>/dev/null || {
            echo "    ⚠️  Skipped (may already exist)"
        }
    done
    
    echo "✅ Import complete!"
fi
