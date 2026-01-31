#!/bin/bash
# =============================================================================
# Health Check Script - Enhanced Version
# =============================================================================
# Checks if all services are running and sends alert if not
# Monitors: n8n, PostgreSQL, Caddy, WAHA
# Add to crontab: */5 * * * * /path/to/healthcheck.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Logging configuration
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/healthcheck.log"
MAX_LOG_SIZE=10485760  # 10MB

# Thresholds
DISK_WARN_THRESHOLD=80
DISK_CRIT_THRESHOLD=90
MEMORY_WARN_THRESHOLD=85

# Initialize failure tracking
declare -a FAILURES=()
declare -a WARNINGS=()

# =============================================================================
# Logging Functions
# =============================================================================

setup_logging() {
    # Create logs directory if it doesn't exist
    if [[ ! -d "${LOG_DIR}" ]]; then
        mkdir -p "${LOG_DIR}"
    fi

    # Rotate log if too large
    if [[ -f "${LOG_FILE}" ]] && [[ $(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}" 2>/dev/null) -gt ${MAX_LOG_SIZE} ]]; then
        mv "${LOG_FILE}" "${LOG_FILE}.old"
    fi
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[${timestamp}] ${level}: ${message}"

    echo "${log_entry}" >> "${LOG_FILE}"
    echo "${log_entry}"
}

log_ok() {
    log "OK" "$1"
}

log_fail() {
    log "FAIL" "$1"
    FAILURES+=("$1")
}

log_warn() {
    log "WARN" "$1"
    WARNINGS+=("$1")
}

# =============================================================================
# Environment Loading
# =============================================================================

load_environment() {
    if [[ -f "${PROJECT_DIR}/.env" ]]; then
        # shellcheck disable=SC2046
        export $(grep -v '^#' "${PROJECT_DIR}/.env" | grep -v '^$' | xargs)
    fi
}

# =============================================================================
# Alert Function
# =============================================================================

send_telegram_alert() {
    local message="$1"

    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && [[ -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" > /dev/null 2>&1 || true
    fi
}

# =============================================================================
# Service Health Checks
# =============================================================================

check_n8n() {
    log "INFO" "Checking n8n health..."

    if curl -sf "http://localhost:5678/healthz" > /dev/null 2>&1; then
        log_ok "n8n healthy"
        return 0
    else
        log_fail "n8n unreachable at http://localhost:5678/healthz"
        return 1
    fi
}

check_postgres() {
    log "INFO" "Checking PostgreSQL health..."

    local pg_user="${POSTGRES_USER:-postgres}"

    if docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T postgres pg_isready -U "${pg_user}" > /dev/null 2>&1; then
        log_ok "PostgreSQL healthy"
        return 0
    else
        log_fail "PostgreSQL unreachable"
        return 1
    fi
}

check_caddy() {
    log "INFO" "Checking Caddy health..."

    # Check if Caddy is responding on port 80
    if curl -sf -o /dev/null -w "%{http_code}" "http://localhost:80" 2>/dev/null | grep -qE "^(200|301|302|308)$"; then
        log_ok "Caddy healthy (responding on port 80)"
        return 0
    fi

    # Alternative: Check if Caddy container is running and healthy
    if docker compose -f "${PROJECT_DIR}/docker-compose.yml" ps caddy 2>/dev/null | grep -q "running"; then
        log_ok "Caddy container running"
        return 0
    fi

    log_fail "Caddy unreachable on localhost:80"
    return 1
}

check_waha() {
    log "INFO" "Checking WAHA health..."

    if curl -sf "http://localhost:3000/api/health" > /dev/null 2>&1; then
        log_ok "WAHA healthy"
        return 0
    else
        log_fail "WAHA unreachable at http://localhost:3000/api/health"
        return 1
    fi
}

# =============================================================================
# Resource Checks
# =============================================================================

check_disk_space() {
    log "INFO" "Checking disk space..."

    # Check root filesystem
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

    if [[ "${disk_usage}" -ge "${DISK_CRIT_THRESHOLD}" ]]; then
        log_fail "Disk usage CRITICAL at ${disk_usage}% (threshold: ${DISK_CRIT_THRESHOLD}%)"
    elif [[ "${disk_usage}" -ge "${DISK_WARN_THRESHOLD}" ]]; then
        log_warn "Disk usage WARNING at ${disk_usage}% (threshold: ${DISK_WARN_THRESHOLD}%)"
    else
        log_ok "Disk usage healthy at ${disk_usage}%"
    fi
}

check_docker_volumes() {
    log "INFO" "Checking Docker volume disk usage..."

    # Get Docker data root usage
    local docker_info
    docker_info=$(docker system df 2>/dev/null || echo "")

    if [[ -n "${docker_info}" ]]; then
        # Extract volumes usage
        local volumes_usage
        volumes_usage=$(echo "${docker_info}" | grep "Volumes" | awk '{print $5}' | sed 's/%//' 2>/dev/null || echo "0")

        if [[ -n "${volumes_usage}" ]] && [[ "${volumes_usage}" =~ ^[0-9]+$ ]]; then
            if [[ "${volumes_usage}" -ge "${DISK_CRIT_THRESHOLD}" ]]; then
                log_fail "Docker volumes usage CRITICAL at ${volumes_usage}%"
            elif [[ "${volumes_usage}" -ge "${DISK_WARN_THRESHOLD}" ]]; then
                log_warn "Docker volumes usage WARNING at ${volumes_usage}%"
            else
                log_ok "Docker volumes usage healthy at ${volumes_usage}%"
            fi
        else
            log_ok "Docker volumes usage: unable to parse, skipping"
        fi

        # Log overall Docker disk usage for reference
        local total_size
        total_size=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "unknown")
        log "INFO" "Docker total disk usage: ${total_size}"
    else
        log_warn "Unable to check Docker disk usage"
    fi
}

check_memory() {
    log "INFO" "Checking memory usage..."

    local mem_usage

    # macOS uses different commands than Linux
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS memory check using vm_stat
        local pages_free pages_active pages_inactive pages_speculative pages_wired page_size total_pages used_percent
        page_size=$(sysctl -n hw.pagesize)
        pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        pages_active=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        pages_inactive=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        pages_speculative=$(vm_stat | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
        pages_wired=$(vm_stat | grep "Pages wired" | awk '{print $4}' | sed 's/\.//')

        local total_mem used_mem
        total_mem=$(sysctl -n hw.memsize)
        # Used = wired + active (conservative estimate)
        used_mem=$(( (pages_wired + pages_active) * page_size ))
        mem_usage=$(( used_mem * 100 / total_mem ))
    else
        # Linux memory check
        mem_usage=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
    fi

    if [[ "${mem_usage}" -ge "${MEMORY_WARN_THRESHOLD}" ]]; then
        log_fail "Memory usage HIGH at ${mem_usage}% (threshold: ${MEMORY_WARN_THRESHOLD}%)"
    else
        log_ok "Memory usage healthy at ${mem_usage}%"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    setup_logging
    load_environment

    log "INFO" "=========================================="
    log "INFO" "Starting health check on ${N8N_HOST:-localhost}"
    log "INFO" "=========================================="

    # Run all service checks (continue even if one fails)
    set +e

    check_n8n
    check_postgres
    check_caddy
    check_waha
    check_disk_space
    check_docker_volumes
    check_memory

    set -e

    log "INFO" "=========================================="

    # Aggregate results and send alert if needed
    local total_failures=${#FAILURES[@]}
    local total_warnings=${#WARNINGS[@]}

    if [[ ${total_failures} -gt 0 ]] || [[ ${total_warnings} -gt 0 ]]; then
        local alert_message=""
        local host_name="${N8N_HOST:-localhost}"

        # Build alert message
        if [[ ${total_failures} -gt 0 ]]; then
            alert_message+="<b>ALERT: Health Check Failed</b>%0A"
            alert_message+="Host: ${host_name}%0A"
            alert_message+="Time: $(date '+%Y-%m-%d %H:%M:%S')%0A%0A"
            alert_message+="<b>FAILURES (${total_failures}):</b>%0A"
            for failure in "${FAILURES[@]}"; do
                alert_message+="- ${failure}%0A"
            done
        fi

        if [[ ${total_warnings} -gt 0 ]]; then
            if [[ -n "${alert_message}" ]]; then
                alert_message+="%0A"
            else
                alert_message+="<b>WARNING: Health Check Issues</b>%0A"
                alert_message+="Host: ${host_name}%0A"
                alert_message+="Time: $(date '+%Y-%m-%d %H:%M:%S')%0A%0A"
            fi
            alert_message+="<b>WARNINGS (${total_warnings}):</b>%0A"
            for warning in "${WARNINGS[@]}"; do
                alert_message+="- ${warning}%0A"
            done
        fi

        # Send single consolidated alert
        send_telegram_alert "${alert_message}"

        log "INFO" "Health check completed with ${total_failures} failure(s) and ${total_warnings} warning(s)"

        if [[ ${total_failures} -gt 0 ]]; then
            exit 1
        fi
    else
        log_ok "All services healthy"
        log "INFO" "Health check completed successfully"
    fi
}

# Run main function
main "$@"
