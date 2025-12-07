# Deployment Guide

Deploy Supabase self-hosted on any server with Docker.

---

## Prerequisites

- Docker Engine 20.10+
- Docker Compose v2+
- Git
- 4GB+ RAM (8GB recommended)
- 20GB+ storage

---

## Quick Deploy (Any VPS/Server)

```bash
# 1. Clone repository
git clone https://github.com/your-org/supabase-sf.git
cd supabase-sf

# 2. Initialize (generates all secrets automatically)
chmod +x ./scripts/*.sh
./scripts/init-instance.sh

# 3. Verify deployment
./scripts/check-health.sh
```

**Access:**
- Dashboard: `http://your-server-ip:8000`
- API: `http://your-server-ip:8000`

---

## EasyPanel Deployment

### Option 1: Compose from Git

1. In EasyPanel, create new project
2. Select **"Compose from Git"**
3. Enter repository URL: `https://github.com/your-org/supabase-sf.git`
4. EasyPanel will auto-detect `docker-compose.yml`

> [!IMPORTANT]
> After deployment, SSH into the container and run:
> ```bash
> ./scripts/init-instance.sh
> ```
> This generates secure secrets. Without this, default insecure values are used.

### Option 2: Manual Setup

1. SSH into your EasyPanel server
2. Follow the Quick Deploy steps above
3. In EasyPanel, add the project directory as a custom app

---

## Production Configuration

### 1. Update URLs in `.env`

```bash
# Change these to your actual domain
SITE_URL=https://yourdomain.com
API_EXTERNAL_URL=https://api.yourdomain.com
SUPABASE_PUBLIC_URL=https://api.yourdomain.com
```

### 2. Configure SMTP (for email auth)

```bash
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=your-sendgrid-api-key
SMTP_SENDER_NAME=Your App
SMTP_ADMIN_EMAIL=admin@yourdomain.com
```

### 3. Enable Full Stack (optional)

```bash
# Start with analytics and image processing
docker compose --profile full up -d
```

### 4. Setup Reverse Proxy (recommended)

Example Nginx config:

```nginx
server {
    listen 80;
    server_name api.yourdomain.com;
    
    location / {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Maintenance

### Regular Backups

```bash
# Manual backup
./scripts/backup.sh

# Automated (cron example - daily at 2am)
0 2 * * * /path/to/supabase-sf/scripts/backup.sh >> /var/log/supabase-backup.log 2>&1
```

### Updates

```bash
# 1. Backup first
./scripts/backup.sh

# 2. Pull latest images
docker compose pull

# 3. Restart
docker compose down
docker compose up -d

# 4. Verify
./scripts/check-health.sh
```

### Monitoring

```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f

# Specific service
docker compose logs -f auth
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Services won't start | `docker compose logs` to check errors |
| Auth failures | Run `./scripts/check-health.sh` to check secret sync |
| Database connection refused | Ensure `supabase-db` is healthy |
| Out of memory | Increase server RAM or reduce pool sizes |

---

## Security Checklist

- [ ] Changed all default secrets via `init-instance.sh`
- [ ] Updated `DASHBOARD_PASSWORD`
- [ ] Configured HTTPS (reverse proxy + SSL)
- [ ] Restricted network access (firewall)
- [ ] Setup regular backups
- [ ] Reviewed `.env` file permissions (chmod 600)
