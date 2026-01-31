# Agent Execution Rules

## Project Overview

This is an n8n workflow automation platform for Solution Press business operations:
- **MojWeb** - Website builder automation (leads, demos, monitoring)
- **MojaFirma** - HR/payroll automation (legal monitoring, newsletters)
- **Investments** - Portfolio tracking automation

Tech stack: n8n, PostgreSQL, Caddy, WAHA (WhatsApp), Docker Compose

## Core Principles

1. **NEVER edit code files directly** - Always spawn an appropriate agent to make changes
2. **ALWAYS** use `model: "opus"` when spawning Task agents
3. **NEVER** omit the model parameter
4. **ALWAYS** spawn parallel agents when tasks are independent
5. Use orchestrator pattern for complex multi-service operations
6. Each agent should handle a focused, atomic task

## No Direct Edits Rule (CRITICAL)

The main Claude instance must NOT use Edit, Write, or NotebookEdit tools for code changes. Instead:

### What the main instance CAN do directly:
- Read files (Read, Glob, Grep)
- Run commands (Bash for git, docker, make, etc.)
- Explore codebase (Task with Explore agent)
- Communicate with user
- Coordinate and spawn agents

### What MUST be delegated to agents:
- Docker Compose modifications (`docker-compose.yml`)
- Shell scripts (`scripts/*.sh`)
- n8n workflow JSON files (`workflows/**/*.json`)
- Caddy configuration (`config/Caddyfile`)
- Environment templates (`.env.example`)
- Makefile changes

### How to delegate:
```
// For infrastructure changes:
Task({
  model: "opus",
  description: "[INFRA-DOCKER] - Add resource limits to containers",
  prompt: "Edit docker-compose.yml to add memory limits..."
})

// For workflow creation:
Task({
  model: "opus",
  description: "[WORKFLOW-MOJWEB] - Create lead scraper workflow",
  prompt: "Create a new n8n workflow that scrapes Booking.com..."
})

// For complex features:
Task({
  model: "opus",
  description: "[ORCH-INFRA] - Implement monitoring stack",
  prompt: "Coordinate implementation of health monitoring..."
})
```

### Exceptions (direct edits allowed):
- `CLAUDE.md` files (configuration, not code)
- Documentation files (`.md`) when explicitly requested
- Git operations (commits, pushes)

## Agent Naming Convention

Every agent MUST have a clear, short prefix name in the description for console visibility.

### Orchestrators (coordinate other agents)

| Name | Purpose |
|------|---------|
| `[ORCH-MAIN]` | Main orchestrator for large multi-service tasks |
| `[ORCH-INFRA]` | Coordinate Docker, Caddy, networking agents |
| `[ORCH-WORKFLOWS]` | Coordinate multiple workflow implementations |
| `[ORCH-DEPLOY]` | Coordinate deployment and migration tasks |

### Infrastructure Worker Agents

| Name | Purpose |
|------|---------|
| `[INFRA-DOCKER]` | Docker Compose, container configuration |
| `[INFRA-CADDY]` | Caddyfile, reverse proxy, SSL |
| `[INFRA-NETWORK]` | Docker networks, ports, security |
| `[INFRA-VOLUMES]` | Volume management, persistence |
| `[INFRA-ENV]` | Environment variables, .env.example |

### Workflow Worker Agents

| Name | Purpose |
|------|---------|
| `[WORKFLOW-MOJWEB]` | MojWeb automation workflows |
| `[WORKFLOW-MOJAFIRMA]` | MojaFirma automation workflows |
| `[WORKFLOW-INVEST]` | Investment tracking workflows |
| `[WORKFLOW-INFRA]` | Infrastructure automation (backup, health) |
| `[WORKFLOW-PERSONAL]` | Personal automation workflows |

### Script Worker Agents

| Name | Purpose |
|------|---------|
| `[SCRIPT-BACKUP]` | Backup and restore scripts |
| `[SCRIPT-HEALTH]` | Health check scripts |
| `[SCRIPT-DEPLOY]` | Deployment scripts |
| `[SCRIPT-UTIL]` | Utility shell scripts |

### Database Worker Agents

| Name | Purpose |
|------|---------|
| `[DB-POSTGRES]` | PostgreSQL configuration |
| `[DB-BACKUP]` | Database backup/restore |
| `[DB-MIGRATE]` | Schema migrations |

### Integration Worker Agents

| Name | Purpose |
|------|---------|
| `[INTEG-WAHA]` | WhatsApp/WAHA integration |
| `[INTEG-TELEGRAM]` | Telegram bot/alerts |
| `[INTEG-GMAIL]` | Gmail/email integration |
| `[INTEG-OPENAI]` | OpenAI API integration |
| `[INTEG-MOJWEB]` | MojWeb API integration |

### Utility Agents

| Name | Purpose |
|------|---------|
| `[EXPLORE-CODEBASE]` | Understand project structure |
| `[EXPLORE-WORKFLOWS]` | Analyze existing n8n workflows |
| `[FIX-BUG]` | Single bug fix |
| `[FIX-CONFIG]` | Fix configuration issues |
| `[FIX-SCRIPT]` | Fix shell script issues |

### Verification Agents

| Name | Purpose |
|------|---------|
| `[VERIFY-COMPOSE]` | Validate docker-compose.yml |
| `[VERIFY-SCRIPTS]` | Shellcheck, syntax validation |
| `[VERIFY-WORKFLOW]` | Validate n8n workflow JSON |
| `[VERIFY-HEALTH]` | Run health checks |
| `[VERIFY-SECURITY]` | Security audit |

### Review Agents

| Name | Purpose |
|------|---------|
| `[REVIEW-SECURITY]` | Security audit (ports, secrets, auth) |
| `[REVIEW-PERF]` | Performance review (resources, limits) |
| `[REVIEW-BACKUP]` | Backup strategy review |

## Usage Examples

### Simple Infrastructure Fix
```
Task({
  model: "opus",
  description: "[INFRA-DOCKER] - Add memory limits to n8n container",
  prompt: "Edit docker-compose.yml to add mem_limit: 1g to n8n service..."
})
```

### New Workflow Implementation
```
Task({
  model: "opus",
  description: "[WORKFLOW-MOJWEB] - Create lead scraper workflow",
  prompt: "Create workflows/mojweb/lead-scraper.json that:
    1. Triggers daily at 06:00
    2. Scrapes Booking.com for properties without websites
    3. Stores leads in MojWeb API
    4. Sends summary to Telegram"
})
```

### Complex Feature (Orchestrator Pattern)
```
Task({
  model: "opus",
  description: "[ORCH-INFRA] - Implement full monitoring stack",
  prompt: "Orchestrate monitoring implementation. Spawn these agents:
    1. [SCRIPT-HEALTH] - Enhanced health check script
    2. [INFRA-DOCKER] - Add healthcheck configs to all services
    3. [WORKFLOW-INFRA] - Create n8n health monitoring workflow
    4. [INTEG-TELEGRAM] - Set up alert integration
    Finally:
    5. [VERIFY-HEALTH] - Test all health checks"
})
```

### Parallel Verification
```
// Spawn verification agents in parallel
Task({
  model: "opus",
  description: "[VERIFY-COMPOSE] - Validate Docker Compose syntax",
})

Task({
  model: "opus",
  description: "[VERIFY-SCRIPTS] - Run shellcheck on all scripts",
})

Task({
  model: "opus",
  description: "[VERIFY-SECURITY] - Audit exposed ports and secrets",
})
```

## Code Style Rules

### General
- No comments unless absolutely necessary for complex logic
- No emojis in code (allowed in user-facing alerts)
- Keep configurations minimal and self-documenting
- Use descriptive naming

### Shell Scripts
- Use `set -euo pipefail` for safety
- Quote all variables: `"${VAR}"`
- Use `shellcheck` for validation
- Add usage/help in script headers

### Docker Compose
- Pin image versions (no `latest` in production)
- Always set resource limits
- Use health checks for all services
- Keep services minimal

### n8n Workflows
- Use descriptive node names
- Add error handling paths
- Include webhook validation
- Document complex logic in node notes

### Commit Messages
- Follow Conventional Commits: `feat:`, `fix:`, `docs:`, `infra:`, `chore:`
- No emojis
- Keep concise and descriptive

## Project-Specific Rules

### Security
- NEVER expose database ports to host
- NEVER commit `.env` files
- ALWAYS use secrets for passwords
- ALWAYS put services behind Caddy (HTTPS)
- ALWAYS enable authentication on WAHA

### Backup Strategy
- PostgreSQL dump included in every backup
- Workflow exports for version control
- 30-day retention minimum
- Test restores periodically

### WhatsApp/WAHA
- Rate limit messages (5-10/day initially)
- Use dedicated phone number
- Log all outgoing messages
- Handle session disconnects gracefully

### n8n Best Practices
- Pin n8n version in production
- Prune execution history (7 days)
- Save execution data for debugging
- Use environment variables for all secrets

## Automatic Agent Spawning Rules

### Post-Edit Auto-Verification

After completing ANY infrastructure changes, automatically spawn verification agents:

```
// After docker-compose edits:
[VERIFY-COMPOSE] - Run docker compose config

// After script edits:
[VERIFY-SCRIPTS] - Run shellcheck

// After workflow edits:
[VERIFY-WORKFLOW] - Validate JSON structure
```

### Sensitive Area Triggers

When editing these paths, AUTOMATICALLY spawn review agents:

| Path Pattern | Auto-Spawn Agent |
|--------------|------------------|
| `docker-compose.yml` | `[VERIFY-COMPOSE]`, `[REVIEW-SECURITY]` |
| `scripts/*.sh` | `[VERIFY-SCRIPTS]` |
| `config/Caddyfile` | `[REVIEW-SECURITY]` |
| `.env.example` | `[REVIEW-SECURITY]` |
| `workflows/**/*.json` | `[VERIFY-WORKFLOW]` |

### Workflow Templates

#### Standard Infrastructure Edit
```
1. Make the requested changes
2. Auto-spawn: [VERIFY-COMPOSE] or [VERIFY-SCRIPTS]
3. If security-related: Auto-spawn [REVIEW-SECURITY]
4. Report results
5. Fix issues automatically if possible
```

#### New Workflow Implementation
```
1. Create the workflow JSON
2. Auto-spawn: [VERIFY-WORKFLOW]
3. Document in docs/WORKFLOWS.md
4. Test with manual trigger
5. Report completion
```

#### Deployment Changes
```
1. Make infrastructure changes
2. Auto-spawn in parallel:
   - [VERIFY-COMPOSE]
   - [VERIFY-SCRIPTS]
   - [REVIEW-SECURITY]
3. Update docs/SETUP.md if needed
4. Report status
```

### Implementation Completion Checklist

After completing any feature, automatically verify:
- [ ] Docker Compose validates (`docker compose config`)
- [ ] Shell scripts pass shellcheck
- [ ] Workflow JSON is valid
- [ ] No secrets in code (only in .env)
- [ ] Security review (if applicable)
- [ ] Documentation updated

Report completion only when ALL applicable checks pass.

## Quick Reference: Common Commands

```bash
# Service management
make up              # Start all services
make down            # Stop all services
make restart         # Restart all services
make logs            # View logs
make status          # Check service status

# Development
make dev             # Start n8n + postgres only (no Caddy/WAHA)
make shell           # Shell into n8n container
make db-shell        # Shell into postgres

# Backup/Restore
make backup          # Create backup
make restore F=file  # Restore from backup
make export          # Export workflows
make import          # Import workflows

# WhatsApp
make waha-status     # Check WAHA status
make waha-qr         # Get QR code for linking

# Maintenance
make update          # Update container images
make clean           # Remove unused resources
```
