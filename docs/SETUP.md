# Setup Guide

Detailed instructions for setting up the automation platform.

## Prerequisites

- Server with Docker installed (Ubuntu 22.04+ recommended)
- Domain name pointed to server
- API keys for MojWeb, Telegram, etc.

## Step 1: Server Preparation

### Hetzner Cloud (Recommended)

1. Create CX22 instance (2 vCPU, 4GB RAM, 40GB SSD) - ~€4.35/month
2. Select Ubuntu 24.04
3. Add your SSH key
4. Choose Falkenstein datacenter (EU)

### Initial Server Setup

```bash
# Connect to server
ssh root@YOUR_SERVER_IP

# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh

# Verify installation
docker --version
docker compose version

# Create non-root user (optional but recommended)
adduser deploy
usermod -aG docker deploy
```

## Step 2: Clone Repository

```bash
# As root or deploy user
cd /srv
git clone git@github.com:solution-press/mojweb-automation.git
cd mojweb-automation

# Set permissions
chmod +x scripts/*.sh
```

## Step 3: Configure Environment

```bash
cp .env.example .env
nano .env
```

### Required Variables

```bash
# n8n access
N8N_HOST=automation.mojweb.site
N8N_USER=admin
N8N_PASSWORD=$(openssl rand -base64 32)

# Database
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$(openssl rand -base64 32)

# MojWeb API (get from dashboard)
MOJWEB_API_URL=https://mojweb.site
MOJWEB_API_KEY=mw_live_xxxxx
```

### Optional Variables

```bash
# Telegram alerts
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_CHAT_ID=-100123456789

# AI for demo generation
OPENAI_API_KEY=sk-xxxxx

# Gmail for outreach
GMAIL_USER=automation@yourdomain.com
GMAIL_APP_PASSWORD=xxxx xxxx xxxx xxxx
```

## Step 4: Configure DNS

Add A record pointing to your server:

```
automation.mojweb.site  →  A  →  123.45.67.89
```

Wait for DNS propagation (usually 5-15 minutes).

## Step 5: Start Services

```bash
make up
```

This will:
1. Pull Docker images
2. Start PostgreSQL
3. Start n8n
4. Start Caddy (auto-obtains SSL)

Verify:
```bash
make status
make logs
```

## Step 6: Access n8n

Open https://automation.mojweb.site

Login with:
- Username: value of `N8N_USER`
- Password: value of `N8N_PASSWORD`

## Step 7: Configure Credentials

In n8n UI, go to **Credentials** and add:

### MojWeb API
- Type: Header Auth
- Name: `Authorization`
- Value: `Bearer mw_live_xxxxx`

### Telegram
- Type: Telegram API
- Bot Token: from BotFather

### OpenAI
- Type: OpenAI API
- API Key: from platform.openai.com

### Gmail
- Type: Gmail OAuth2 or SMTP
- For OAuth2: Follow Google Cloud Console setup
- For SMTP: Use App Password

## Step 8: Setup Cron Jobs

```bash
crontab -e
```

Add:
```cron
# Daily backup at 03:00
0 3 * * * /srv/mojweb-automation/scripts/backup.sh >> /var/log/n8n-backup.log 2>&1

# Health check every 5 minutes
*/5 * * * * /srv/mojweb-automation/scripts/healthcheck.sh >> /var/log/n8n-health.log 2>&1
```

## Step 9: Import Workflows

If you have existing workflows:

```bash
make import
```

Or create new ones in n8n UI.

## Step 10: Test

1. Create a simple test workflow in n8n
2. Trigger it manually
3. Check execution logs
4. Verify Telegram alerts work

## Firewall Configuration

If using UFW:

```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
ufw enable
```

Port 5678 should NOT be exposed directly - Caddy handles HTTPS.

## Security Checklist

- [ ] Strong passwords in .env
- [ ] SSH key authentication only (disable password)
- [ ] Firewall enabled
- [ ] Regular backups configured
- [ ] Monitoring alerts working
- [ ] n8n accessed via HTTPS only

## Updating

```bash
cd /srv/mojweb-automation
git pull
make update
```

## Troubleshooting

### SSL certificate not working

```bash
# Check Caddy logs
docker compose logs caddy

# Verify DNS
dig automation.mojweb.site
```

### n8n database connection error

```bash
# Check postgres is running
docker compose ps
docker compose logs postgres

# Verify credentials match
grep POSTGRES .env
```

### Webhook not receiving data

- Verify webhook URL is accessible from internet
- Check n8n execution logs
- Ensure `WEBHOOK_URL` in .env is correct
