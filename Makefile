.PHONY: help up down restart logs logs-n8n logs-postgres logs-waha status backup restore import export update clean shell db-shell waha-status

# Default target
help:
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║           Solution Press Automation - Commands                ║"
	@echo "╠═══════════════════════════════════════════════════════════════╣"
	@echo "║  Service Management:                                          ║"
	@echo "║    make up          - Start all services                      ║"
	@echo "║    make down        - Stop all services                       ║"
	@echo "║    make restart     - Restart all services                    ║"
	@echo "║    make status      - Show service status                     ║"
	@echo "║                                                               ║"
	@echo "║  Logs:                                                        ║"
	@echo "║    make logs        - Follow all logs                         ║"
	@echo "║    make logs-n8n    - Follow n8n logs only                    ║"
	@echo "║    make logs-waha   - Follow WAHA logs only                   ║"
	@echo "║                                                               ║"
	@echo "║  WhatsApp (WAHA):                                             ║"
	@echo "║    make waha-status - Check WhatsApp session status           ║"
	@echo "║    make waha-qr     - Show QR code for linking                ║"
	@echo "║                                                               ║"
	@echo "║  Backup & Restore:                                            ║"
	@echo "║    make backup      - Create full backup                      ║"
	@echo "║    make restore F=  - Restore from backup (F=filename)        ║"
	@echo "║                                                               ║"
	@echo "║  Workflows:                                                   ║"
	@echo "║    make export      - Export all workflows to ./workflows     ║"
	@echo "║    make import      - Import workflows from ./workflows       ║"
	@echo "║                                                               ║"
	@echo "║  Maintenance:                                                 ║"
	@echo "║    make update      - Pull latest images and restart          ║"
	@echo "║    make clean       - Remove unused Docker resources          ║"
	@echo "║    make shell       - Open shell in n8n container             ║"
	@echo "║    make db-shell    - Open PostgreSQL shell                   ║"
	@echo "╚═══════════════════════════════════════════════════════════════╝"

# -----------------------------------------------------------------------------
# Service Management
# -----------------------------------------------------------------------------

up:
	@echo "🚀 Starting services..."
	docker compose up -d
	@echo "✅ Services started. Access n8n at https://$$(grep N8N_HOST .env | cut -d '=' -f2)"

down:
	@echo "🛑 Stopping services..."
	docker compose down
	@echo "✅ Services stopped."

restart:
	@echo "🔄 Restarting services..."
	docker compose restart
	@echo "✅ Services restarted."

status:
	@echo "📊 Service Status:"
	@docker compose ps
	@echo ""
	@echo "📈 Resource Usage:"
	@docker stats --no-stream $$(docker compose ps -q) 2>/dev/null || true

# -----------------------------------------------------------------------------
# Logs
# -----------------------------------------------------------------------------

logs:
	docker compose logs -f

logs-n8n:
	docker compose logs -f n8n

logs-postgres:
	docker compose logs -f postgres

logs-waha:
	docker compose logs -f waha

# -----------------------------------------------------------------------------
# WhatsApp (WAHA)
# -----------------------------------------------------------------------------

waha-status:
	@echo "📱 WhatsApp Session Status:"
	@curl -s http://localhost:3000/api/sessions/default 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "WAHA not running or session not started"

waha-qr:
	@echo "📱 Scan this QR code with WhatsApp:"
	@echo "   Open http://localhost:3000/dashboard to see QR code"
	@echo "   Or fetch: curl http://localhost:3000/api/sessions/default/auth/qr"

# -----------------------------------------------------------------------------
# Backup & Restore
# -----------------------------------------------------------------------------

backup:
	@echo "💾 Creating backup..."
	@./scripts/backup.sh
	@echo "✅ Backup complete. Check ./backups/"

restore:
ifndef F
	@echo "❌ Error: Specify backup file with F=filename"
	@echo "   Example: make restore F=backup_20260126_120000.tar.gz"
	@exit 1
endif
	@echo "⚠️  This will overwrite current data. Continue? [y/N]"
	@read -r confirm && [ "$$confirm" = "y" ] || exit 1
	@./scripts/restore.sh $(F)

# -----------------------------------------------------------------------------
# Workflow Management
# -----------------------------------------------------------------------------

export:
	@echo "📤 Exporting workflows..."
	@./scripts/export-workflows.sh
	@echo "✅ Workflows exported to ./workflows/"

import:
	@echo "📥 Importing workflows..."
	@./scripts/import-workflows.sh
	@echo "✅ Workflows imported."

# -----------------------------------------------------------------------------
# Maintenance
# -----------------------------------------------------------------------------

update:
	@echo "⬆️  Updating images..."
	docker compose pull
	docker compose up -d
	@echo "✅ Updated to latest versions."

clean:
	@echo "🧹 Cleaning unused Docker resources..."
	docker system prune -f
	docker volume prune -f
	@echo "✅ Cleanup complete."

shell:
	docker compose exec n8n /bin/sh

db-shell:
	docker compose exec postgres psql -U $$(grep POSTGRES_USER .env | cut -d '=' -f2) -d n8n

# -----------------------------------------------------------------------------
# Development
# -----------------------------------------------------------------------------

dev:
	@echo "🔧 Starting in development mode (no Caddy)..."
	docker compose up -d n8n postgres
	@echo "✅ n8n available at http://localhost:5678"

healthcheck:
	@./scripts/healthcheck.sh
