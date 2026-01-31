# Solution Press Automation

Workflow automation platform powered by n8n for MojWeb, MojaFirma, and internal operations.

## Quick Start

```bash
# 1. Clone repository
git clone git@github.com:solution-press/mojweb-automation.git
cd mojweb-automation

# 2. Configure environment
cp .env.example .env
nano .env  # Fill in your values

# 3. Start services
make up

# 4. Access n8n
# Open https://automation.mojweb.site (or your configured domain)
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| n8n | 5678 | Workflow automation engine |
| PostgreSQL | 5432 | Database for n8n |
| Caddy | 80/443 | Reverse proxy with auto-SSL |
| WAHA | 3000 | WhatsApp HTTP API (self-hosted) |

## Commands

```bash
make help         # Show all available commands

# Service management
make up           # Start all services
make down         # Stop all services
make restart      # Restart all services
make status       # Show service status
make logs         # Follow all logs
make logs-n8n     # Follow n8n logs only

# Backup & restore
make backup       # Create full backup
make restore F=backup_xxx.tar.gz  # Restore from backup

# Workflows
make export       # Export workflows to ./workflows/
make import       # Import workflows from ./workflows/

# Maintenance
make update       # Update to latest images
make shell        # Open shell in n8n container
make db-shell     # Open PostgreSQL shell
```

## Directory Structure

```
mojweb-automation/
├── docker-compose.yml      # Service definitions
├── .env                    # Environment variables (git-ignored)
├── .env.example            # Environment template
├── Makefile                # Common commands
│
├── workflows/              # Exported n8n workflows (version controlled)
│   ├── mojweb/             # MojWeb automations
│   ├── mojafirma/          # MojaFirma automations
│   ├── investments/        # Portfolio tracking
│   ├── personal/           # Personal automations
│   └── infrastructure/     # Monitoring, backups
│
├── scripts/
│   ├── backup.sh           # Daily backup script
│   ├── restore.sh          # Restore from backup
│   ├── export-workflows.sh # Export for version control
│   ├── import-workflows.sh # Import into n8n
│   └── healthcheck.sh      # Service health monitoring
│
├── config/
│   └── Caddyfile           # Reverse proxy configuration
│
├── backups/                # Backup storage (git-ignored)
│
└── docs/
    ├── SETUP.md            # Detailed setup instructions
    ├── WORKFLOWS.md        # Workflow documentation
    └── TROUBLESHOOTING.md  # Common issues
```

## Workflows

### MojWeb
- **Lead Scraper** - Discover accommodations without websites on Booking.com
- **Demo Generator** - Automatically create demo websites for prospects
- **Uptime Monitor** - Monitor all published customer websites
- **Review Aggregator** - Pull and sync reviews from Booking/Google
- **Follow-up Sequence** - Automated email nurturing for leads

### MojaFirma
- **Narodne Novine Monitor** - Track legal changes affecting HR/payroll
- **Newsletter Generator** - Auto-generate weekly client updates

### Investments
- **Portfolio Tracker** - Daily gold/silver/ZSE price monitoring
- **Price Alerts** - Notifications when prices cross thresholds

### Infrastructure
- **Daily Backup** - Automated backup of all data
- **Health Monitor** - Service availability checks

## Backup Strategy

Backups run daily at 03:00 via cron:

```bash
# Add to crontab
0 3 * * * /srv/mojweb-automation/scripts/backup.sh
```

Each backup includes:
- PostgreSQL database dump
- n8n workflow exports
- n8n data volume

Backups are retained for 30 days (configurable via `BACKUP_RETENTION_DAYS`).

## Monitoring

Add healthcheck to crontab for alerts:

```bash
# Check every 5 minutes
*/5 * * * * /srv/mojweb-automation/scripts/healthcheck.sh
```

Alerts are sent via Telegram when:
- n8n is unreachable
- PostgreSQL is down
- Disk usage exceeds 80%

## API Keys Required

| Service | Where to get | Used for |
|---------|--------------|----------|
| MojWeb API | mojweb.site/dashboard/settings/api | Lead management, demos |
| Telegram Bot | @BotFather | Alerts |
| OpenAI | platform.openai.com | Demo copy generation |
| Gmail | Google Cloud Console | Outreach emails |
| WAHA | No keys needed - just QR scan | WhatsApp outreach |

## WhatsApp Setup (WAHA)

WAHA provides self-hosted WhatsApp API. No Meta Business account needed.

### Connect Your WhatsApp

1. Start services: `make up`
2. Open WAHA dashboard: http://localhost:3000/dashboard
3. Login with credentials from `.env`
4. Click "Start New Session"
5. Open WhatsApp on phone → Settings → Linked Devices → Link a Device
6. Scan QR code
7. Done! ✅

### Send Message via API

```bash
curl -X POST http://localhost:3000/api/sendText \
  -H "Content-Type: application/json" \
  -d '{
    "chatId": "385911234567@c.us",
    "text": "Hello from automation!"
  }'
```

### Use in n8n

1. Install WAHA node: Settings → Community nodes → `@devlikeapro/n8n-nodes-waha`
2. Add WAHA credentials (URL: `http://waha:3000`)
3. Use "WAHA" nodes in workflows

### ⚠️ Important Warnings

- **Use a secondary phone number** - not your main one
- **Start slow** - 5-10 messages/day initially
- **Risk of ban** - WhatsApp doesn't officially support this
- **Session drops** - may need to re-scan QR occasionally

## Deployment

### Initial Server Setup (Hetzner CX22 recommended)

```bash
# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
apt install docker-compose-plugin

# Clone and configure
git clone git@github.com:solution-press/mojweb-automation.git /srv/mojweb-automation
cd /srv/mojweb-automation
cp .env.example .env
nano .env

# Start
make up

# Setup cron jobs
crontab -e
# Add:
# 0 3 * * * /srv/mojweb-automation/scripts/backup.sh
# */5 * * * * /srv/mojweb-automation/scripts/healthcheck.sh
```

### DNS Configuration

Point your domain to the server:
```
automation.mojweb.site  →  A  →  YOUR_SERVER_IP
```

Caddy will automatically obtain SSL certificate.

## Troubleshooting

### n8n won't start
```bash
make logs-n8n
# Check for database connection errors
make logs-postgres
```

### Workflows not executing
- Check n8n UI for execution errors
- Verify API keys in credentials
- Check rate limits on external APIs

### Out of disk space
```bash
make clean          # Remove unused Docker resources
make backup         # Backup first, then...
# Manually delete old backups if needed
```

## License

Proprietary - Solution Press d.o.o.
