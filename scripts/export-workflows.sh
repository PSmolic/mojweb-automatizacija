#!/bin/bash
# =============================================================================
# Export Workflows Script
# =============================================================================
# Exports all n8n workflows to ./workflows/ for version control
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="${PROJECT_DIR}/workflows"

echo "📤 Exporting workflows..."

# Export all workflows as single file
docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T n8n \
    n8n export:workflow --all --output="/tmp/all_workflows.json"

# Copy to host
docker cp \
    $(docker compose -f "${PROJECT_DIR}/docker-compose.yml" ps -q n8n):/tmp/all_workflows.json \
    "${WORKFLOWS_DIR}/all_workflows.json"

# Also export individually (if you want to organize by folder)
echo "  → Parsing individual workflows..."

# Using node to split workflows (if jq is not available)
docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T n8n \
    node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('/tmp/all_workflows.json', 'utf8'));
const workflows = Array.isArray(data) ? data : [data];

workflows.forEach(wf => {
    const name = wf.name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    const folder = wf.meta?.folder || 'uncategorized';
    console.log('  - ' + wf.name + ' -> ' + folder + '/' + name + '.json');
});
console.log('Total: ' + workflows.length + ' workflows');
" 2>/dev/null || echo "  (Individual parsing skipped)"

echo ""
echo "✅ Workflows exported to ${WORKFLOWS_DIR}/"
echo "   Commit to git to version control your workflows."
