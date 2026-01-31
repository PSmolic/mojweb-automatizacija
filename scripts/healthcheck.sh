#!/bin/bash
# =============================================================================
# Health Check Script
# =============================================================================
# Checks if all services are running and sends alert if not
# Add to crontab: */5 * * * * /path/to/healthcheck.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "${PROJECT_DIR}/.env" ]; then
    export $(grep -v '^#' "${PROJECT_DIR}/.env" | xargs)
fi

# Function to send Telegram alert
send_alert() {
    local message="$1"
    if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" > /dev/null
    fi
    echo "$message"
}

# Check n8n
if ! curl -sf "http://localhost:5678/healthz" > /dev/null 2>&1; then
    send_alert "🔴 <b>ALERT:</b> n8n is DOWN on ${N8N_HOST}"
    exit 1
fi

# Check PostgreSQL
if ! docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T postgres pg_isready -U "${POSTGRES_USER}" > /dev/null 2>&1; then
    send_alert "🔴 <b>ALERT:</b> PostgreSQL is DOWN on ${N8N_HOST}"
    exit 1
fi

# Check disk space (alert if > 80%)
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "${DISK_USAGE}" -gt 80 ]; then
    send_alert "⚠️ <b>WARNING:</b> Disk usage at ${DISK_USAGE}% on ${N8N_HOST}"
fi

# All good
echo "✅ All services healthy"
