# Troubleshooting Guide

Common issues and solutions.

## Service Issues

### n8n won't start

**Symptoms:** Container keeps restarting

**Check logs:**
```bash
make logs-n8n
```

**Common causes:**
1. Database not ready - wait for postgres healthcheck
2. Invalid environment variables
3. Port 5678 already in use

**Solution:**
```bash
make down
make up
```

### Database connection failed

**Check postgres:**
```bash
make logs-postgres
docker compose exec postgres pg_isready
```

**Reset database:**
```bash
make down
docker volume rm mojweb-automation_postgres_data
make up
```

### SSL certificate issues

**Check Caddy:**
```bash
docker compose logs caddy
```

**Common causes:**
1. DNS not propagated yet
2. Port 80/443 blocked by firewall
3. Domain misconfigured

**Verify DNS:**
```bash
dig automation.mojweb.site
```

## Workflow Issues

### Webhook not triggering

1. Check webhook URL is correct
2. Verify external accessibility
3. Check n8n execution logs

### API calls failing

1. Verify credentials in n8n
2. Check API key permissions
3. Look for rate limiting

### Emails not sending

1. Check Gmail credentials
2. Verify app password is correct
3. Check spam folder

## Performance Issues

### Slow workflow execution

1. Check server resources: `make status`
2. Reduce concurrent executions
3. Optimize workflow logic

### Running out of disk space

```bash
# Check usage
df -h

# Clean Docker
make clean

# Remove old backups
ls -la backups/
rm backups/backup_old.tar.gz
```

## Recovery

### Restore from backup

```bash
make restore F=backup_20260126_120000.tar.gz
```

### Complete reinstall

```bash
make down
docker volume rm mojweb-automation_n8n_data mojweb-automation_postgres_data
make up
make import  # If you have exported workflows
```
