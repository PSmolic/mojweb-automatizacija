#!/bin/bash
# =============================================================================
# Deployment Script for Solution Press Automation Platform
# =============================================================================
# Deploys n8n automation platform to a fresh Hetzner VPS
# Tested on: Ubuntu 22.04/24.04, Debian 11/12
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_NAME=$(basename "$0")
INSTALL_DIR="/srv/mojweb-automation"
REPO_URL="https://github.com/PSmolic/mojweb-automatizacija.git"
LOG_FILE="/var/log/mojweb-deploy.log"

# Parameters
DOMAIN=""
EMAIL=""
SKIP_DOCKER=false

# =============================================================================
# Colors for Output
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} --domain DOMAIN --email EMAIL [OPTIONS]

Deploy n8n automation platform to a Hetzner VPS.

Required:
  -d, --domain DOMAIN    Domain name for n8n (e.g., automation.mojweb.site)
  -e, --email EMAIL      Email for SSL certificate registration

Options:
  --skip-docker          Skip Docker installation (if already installed)
  -h, --help             Show this help message

Examples:
  ${SCRIPT_NAME} --domain automation.mojweb.site --email admin@example.com
  ${SCRIPT_NAME} -d automation.mojweb.site -e admin@example.com --skip-docker

Requirements:
  - Ubuntu 22.04+ or Debian 11+
  - Root access or sudo privileges
  - Domain DNS configured to point to this server

EOF
    exit 0
}

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1" >> "${LOG_FILE}" 2>/dev/null || true
}

print_step() {
    local step_num="$1"
    local message="$2"
    echo -e "\n${BLUE}[Step ${step_num}]${NC} ${message}"
    log "[Step ${step_num}] ${message}"
}

print_success() {
    echo -e "  ${GREEN}[OK]${NC} $1"
    log "[OK] $1"
}

print_error() {
    echo -e "  ${RED}[ERROR]${NC} $1" >&2
    log "[ERROR] $1"
}

print_warning() {
    echo -e "  ${YELLOW}[WARNING]${NC} $1"
    log "[WARNING] $1"
}

print_info() {
    echo -e "  ${BLUE}[INFO]${NC} $1"
    log "[INFO] $1"
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup_on_error() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        echo ""
        print_error "Deployment failed with exit code ${exit_code}"
        print_error "Check log file for details: ${LOG_FILE}"
        echo ""
        echo "To resume deployment, fix the issue and run:"
        echo "  ${SCRIPT_NAME} --domain ${DOMAIN} --email ${EMAIL}"
        echo ""
    fi
}

trap cleanup_on_error EXIT

# =============================================================================
# Argument Parsing
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            --skip-docker)
                SKIP_DOCKER=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    if [[ -z "${DOMAIN}" ]]; then
        print_error "Domain is required. Use --domain or -d to specify."
        exit 1
    fi

    if [[ -z "${EMAIL}" ]]; then
        print_error "Email is required. Use --email or -e to specify."
        exit 1
    fi
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
    print_success "Running as root"
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "${ID}" in
            ubuntu|debian)
                print_success "Operating system: ${PRETTY_NAME}"
                ;;
            *)
                print_error "Unsupported OS: ${ID}. Only Ubuntu and Debian are supported."
                exit 1
                ;;
        esac
    else
        print_error "Cannot detect operating system. /etc/os-release not found."
        exit 1
    fi
}

check_dns() {
    print_info "Checking DNS resolution for ${DOMAIN}..."

    local server_ip
    local resolved_ip

    server_ip=$(curl -4 -sf https://ifconfig.me 2>/dev/null || curl -4 -sf https://ipinfo.io/ip 2>/dev/null || echo "")

    if [[ -z "${server_ip}" ]]; then
        print_warning "Could not determine server's public IP. Skipping DNS check."
        return 0
    fi

    resolved_ip=$(dig +short "${DOMAIN}" A 2>/dev/null | head -1 || echo "")

    if [[ -z "${resolved_ip}" ]]; then
        print_error "Domain ${DOMAIN} does not resolve to any IP address"
        print_error "Please configure DNS A record: ${DOMAIN} -> ${server_ip}"
        exit 1
    fi

    if [[ "${resolved_ip}" != "${server_ip}" ]]; then
        print_warning "Domain ${DOMAIN} resolves to ${resolved_ip}, but server IP is ${server_ip}"
        echo ""
        read -p "Continue anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Domain ${DOMAIN} correctly resolves to ${server_ip}"
    fi
}

check_ports() {
    print_info "Checking required ports..."

    local ports_in_use=()

    for port in 80 443; do
        if ss -tuln | grep -q ":${port} "; then
            ports_in_use+=("${port}")
        fi
    done

    if [[ ${#ports_in_use[@]} -gt 0 ]]; then
        print_warning "Ports already in use: ${ports_in_use[*]}"
        print_warning "These ports are required for Caddy (HTTPS proxy)"
        echo ""
        read -p "Stop existing services and continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Ports 80 and 443 are available"
    fi
}

# =============================================================================
# Docker Installation
# =============================================================================

install_docker() {
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        print_success "Docker and Docker Compose already installed"
        docker --version
        docker compose version
        return 0
    fi

    print_info "Installing Docker..."

    apt-get update -qq
    apt-get install -y -qq curl ca-certificates gnupg

    curl -fsSL https://get.docker.com | sh

    if ! command -v docker &> /dev/null; then
        print_error "Docker installation failed"
        exit 1
    fi

    systemctl enable docker
    systemctl start docker

    print_success "Docker installed successfully"
    docker --version

    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose not available. Please install Docker Compose v2."
        exit 1
    fi

    print_success "Docker Compose available"
    docker compose version
}

# =============================================================================
# Application Setup
# =============================================================================

setup_application() {
    print_info "Setting up application directory..."

    apt-get install -y -qq git openssl

    if [[ -d "${INSTALL_DIR}" ]]; then
        print_info "Directory exists, pulling latest changes..."
        cd "${INSTALL_DIR}"
        git pull origin main || git pull origin master || true
    else
        print_info "Cloning repository..."
        git clone "${REPO_URL}" "${INSTALL_DIR}"
        cd "${INSTALL_DIR}"
    fi

    print_success "Application code ready at ${INSTALL_DIR}"

    chmod +x scripts/*.sh 2>/dev/null || true
    print_success "Scripts made executable"
}

setup_environment() {
    print_info "Configuring environment variables..."

    cd "${INSTALL_DIR}"

    if [[ ! -f .env ]]; then
        cp .env.example .env
        print_success "Created .env from .env.example"
    else
        print_warning ".env already exists, preserving existing configuration"
        print_info "Updating domain and email settings only..."
    fi

    local postgres_password
    local n8n_password
    local waha_password
    local waha_api_key

    postgres_password=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    n8n_password=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    waha_password=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    waha_api_key=$(openssl rand -hex 32)

    sed -i "s|^N8N_HOST=.*|N8N_HOST=${DOMAIN}|" .env
    print_success "Set N8N_HOST=${DOMAIN}"

    if grep -q "^POSTGRES_PASSWORD=CHANGE_ME" .env; then
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${postgres_password}|" .env
        print_success "Generated secure POSTGRES_PASSWORD"
    fi

    if grep -q "^N8N_PASSWORD=CHANGE_ME" .env; then
        sed -i "s|^N8N_PASSWORD=.*|N8N_PASSWORD=${n8n_password}|" .env
        print_success "Generated secure N8N_PASSWORD"
    fi

    if grep -q "^WAHA_PASSWORD=CHANGE_ME" .env; then
        sed -i "s|^WAHA_PASSWORD=.*|WAHA_PASSWORD=${waha_password}|" .env
        print_success "Generated secure WAHA_PASSWORD"
    fi

    if grep -q "^WAHA_API_KEY=CHANGE_ME" .env; then
        sed -i "s|^WAHA_API_KEY=.*|WAHA_API_KEY=${waha_api_key}|" .env
        print_success "Generated secure WAHA_API_KEY"
    fi

    chmod 600 .env
    print_success "Environment configured"
}

# =============================================================================
# Firewall Configuration
# =============================================================================

configure_firewall() {
    print_info "Configuring firewall..."

    if ! command -v ufw &> /dev/null; then
        apt-get install -y -qq ufw
    fi

    ufw --force reset > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1

    ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
    ufw allow 80/tcp comment 'HTTP' > /dev/null 2>&1
    ufw allow 443/tcp comment 'HTTPS' > /dev/null 2>&1

    ufw --force enable > /dev/null 2>&1

    print_success "UFW firewall enabled"
    print_success "Allowed ports: 22 (SSH), 80 (HTTP), 443 (HTTPS)"
}

# =============================================================================
# Start Services
# =============================================================================

start_services() {
    print_info "Starting services..."

    cd "${INSTALL_DIR}"

    docker compose pull

    docker compose up -d

    print_success "Containers started"
}

wait_for_healthy() {
    print_info "Waiting for services to be healthy..."

    local max_attempts=60
    local attempt=1

    while [[ ${attempt} -le ${max_attempts} ]]; do
        local healthy_count
        healthy_count=$(docker compose ps --format json 2>/dev/null | grep -c '"Health":"healthy"' || echo "0")

        local total_services=4

        echo -ne "\r  Checking health... (${attempt}/${max_attempts}) - ${healthy_count}/${total_services} healthy"

        if [[ ${healthy_count} -ge 3 ]]; then
            echo ""
            print_success "Core services are healthy"
            return 0
        fi

        sleep 5
        ((attempt++))
    done

    echo ""
    print_warning "Some services may still be starting up"
    print_info "Check status with: docker compose ps"
}

run_healthcheck() {
    print_info "Running health check..."

    if [[ -x "${INSTALL_DIR}/scripts/healthcheck.sh" ]]; then
        "${INSTALL_DIR}/scripts/healthcheck.sh" || true
    else
        print_warning "Health check script not found or not executable"
    fi
}

# =============================================================================
# Cron Jobs
# =============================================================================

setup_cron_jobs() {
    print_info "Setting up cron jobs..."

    local backup_cron="0 3 * * * ${INSTALL_DIR}/scripts/backup.sh >> /var/log/n8n-backup.log 2>&1"

    (crontab -l 2>/dev/null | grep -v "backup.sh" || true; echo "${backup_cron}") | crontab -

    print_success "Daily backup scheduled at 03:00"

    echo ""
    read -p "Enable health check every 5 minutes? (Y/n): " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        local health_cron="*/5 * * * * ${INSTALL_DIR}/scripts/healthcheck.sh >> /var/log/n8n-health.log 2>&1"
        (crontab -l 2>/dev/null | grep -v "healthcheck.sh" || true; echo "${health_cron}") | crontab -
        print_success "Health check scheduled every 5 minutes"
    else
        print_info "Skipped health check cron job"
    fi
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    local n8n_password
    local n8n_user

    cd "${INSTALL_DIR}"
    n8n_password=$(grep "^N8N_PASSWORD=" .env | cut -d'=' -f2)
    n8n_user=$(grep "^N8N_USER=" .env | cut -d'=' -f2)

    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}   Deployment Complete!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  ${BLUE}n8n URL:${NC}      https://${DOMAIN}"
    echo -e "  ${BLUE}Username:${NC}     ${n8n_user}"
    echo -e "  ${BLUE}Password:${NC}     ${n8n_password}"
    echo ""
    echo -e "  ${YELLOW}Credentials are stored in:${NC} ${INSTALL_DIR}/.env"
    echo ""
    echo -e "${GREEN}------------------------------------------------------------${NC}"
    echo -e "${GREEN}   Next Steps${NC}"
    echo -e "${GREEN}------------------------------------------------------------${NC}"
    echo ""
    echo "  1. Access n8n at https://${DOMAIN}"
    echo "  2. Log in with the credentials above"
    echo "  3. Configure additional credentials in n8n UI:"
    echo "     - MojWeb API (Header Auth)"
    echo "     - Telegram Bot (for alerts)"
    echo "     - OpenAI API (for AI features)"
    echo "     - Gmail SMTP (for email)"
    echo ""
    echo "  4. Import workflows:"
    echo "     cd ${INSTALL_DIR} && make import"
    echo ""
    echo "  5. For WhatsApp integration:"
    echo "     - Visit http://localhost:3000/dashboard"
    echo "     - Scan QR code with your phone"
    echo ""
    echo -e "${GREEN}------------------------------------------------------------${NC}"
    echo -e "${GREEN}   Useful Commands${NC}"
    echo -e "${GREEN}------------------------------------------------------------${NC}"
    echo ""
    echo "  cd ${INSTALL_DIR}"
    echo "  make status        # Check service status"
    echo "  make logs          # View logs"
    echo "  make restart       # Restart all services"
    echo "  make backup        # Create backup"
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo ""

    log "Deployment completed successfully"
    log "n8n URL: https://${DOMAIN}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}   Solution Press Automation - Deployment Script${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""

    parse_arguments "$@"

    mkdir -p "$(dirname "${LOG_FILE}")"
    log "Starting deployment for domain: ${DOMAIN}"

    print_step "1/9" "Pre-flight checks"
    check_root
    check_os
    check_dns
    check_ports

    print_step "2/9" "Installing Docker"
    if [[ "${SKIP_DOCKER}" == true ]]; then
        print_info "Skipping Docker installation (--skip-docker)"
        if ! command -v docker &> /dev/null; then
            print_error "Docker not found. Remove --skip-docker flag to install."
            exit 1
        fi
        print_success "Docker is available"
    else
        install_docker
    fi

    print_step "3/9" "Setting up application"
    setup_application

    print_step "4/9" "Configuring environment"
    setup_environment

    print_step "5/9" "Configuring firewall"
    configure_firewall

    print_step "6/9" "Starting services"
    start_services

    print_step "7/9" "Waiting for services"
    wait_for_healthy

    print_step "8/9" "Running health check"
    run_healthcheck

    print_step "9/9" "Setting up cron jobs"
    setup_cron_jobs

    print_summary
}

main "$@"
