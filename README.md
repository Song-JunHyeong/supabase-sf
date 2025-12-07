# Supabase Self-Hosted

Docker Compose setup for deploying the complete Supabase stack on your local machine or own server.

> [!CAUTION]
> **This repository is for Self-hosted only.**  
> If you're using [Supabase Cloud](https://supabase.com/dashboard), refer to the [official documentation](https://supabase.com/docs) instead.

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/your-org/supabase-sf.git
cd supabase-sf

# 2. Initialize (auto-generates secure secrets)
./scripts/init-instance.sh

# Or manually:
# cp .env.example .env
# (edit .env, then:)
# docker compose up -d
```

**Access**:
- **Studio Dashboard**: http://localhost:8000
- **API**: http://localhost:8000

---

## ⚠️ Immutable Secrets

> [!CAUTION]
> **The following values are stored inside the system at first deployment.**  
> Changing only `.env` after deployment will **BREAK your system**.

| Key | Storage Location | Impact When Changed |
|-----|------------------|---------------------|
| `POSTGRES_PASSWORD` | 5 DB roles (`authenticator`, `pgbouncer`, `supabase_auth_admin`, `supabase_functions_admin`, `supabase_storage_admin`) | All service DB connections fail |
| `JWT_SECRET` | DB setting `app.settings.jwt_secret` | Auth, REST API, Realtime JWT verification fails |
| `VAULT_ENC_KEY` | Supavisor encrypted data | Connection pooler decryption fails |
| `ANON_KEY` / `SERVICE_ROLE_KEY` | JWT tokens signed with `JWT_SECRET` | Tokens invalidated when JWT_SECRET changes |

**For key rotation**: See [docs/KEY_ROTATION.md](./docs/KEY_ROTATION.md)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Kong (API Gateway)                        │
│                         :8000 (HTTP) / :8443 (HTTPS)                │
└─────────────────────────────────────────────────────────────────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
    ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
    │  Auth   │   │  REST   │   │Realtime │   │ Storage │
    │(GoTrue) │   │(PostgREST)│ │         │   │         │
    └────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘
         │              │              │              │
         └──────────────┴──────┬───────┴──────────────┘
                               ▼
                    ┌─────────────────────┐
                    │     Supavisor       │
                    │ (Connection Pooler) │
                    │   :5432 / :6543     │
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │     PostgreSQL      │
                    │   (supabase/postgres)│
                    └─────────────────────┘

Supporting Services:
├── Studio (Dashboard) - :3000 (internal)
├── Edge Functions (Deno) - /functions/v1/*
├── postgres-meta - DB management API
├── ImgProxy - Image transformation
├── Vector - Log collection
└── Logflare (Analytics) - :4000
```

---

## Repository Structure

```
supabase-sf/
├── docker-compose.yml   # Main orchestration file
├── .env.example         # Environment template (copy to .env)
├── scripts/             # Operational scripts
│   ├── init-instance.sh     # First-time setup (auto-generates secrets)
│   ├── rotate-*.sh          # Key rotation scripts
│   ├── check-health.sh      # Health check & secret sync validation
│   └── reset.sh             # Full reset
├── volumes/             # Docker volumes for data persistence
│   ├── db/              # PostgreSQL init scripts & data
│   ├── storage/         # File storage
│   └── functions/       # Edge Functions
├── supabase/            # Supabase CLI local development config
│   ├── config.toml      # CLI configuration
│   ├── migrations/      # User-defined DB migrations
│   ├── functions/       # User-defined Edge Functions
│   └── seed.sql         # Initial seed data
└── docs/                # Documentation
```

> [!NOTE]
> **`volumes/` vs `supabase/` 차이점**:
> - `volumes/db/`: Docker self-host 배포 시 DB 초기화에 사용되는 시스템 SQL 파일들
> - `supabase/`: Supabase CLI 로컬 개발용 설정 (config.toml, 사용자 마이그레이션 등)

---

## Scripts Workflow

| Script | Purpose | Downtime | Side Effects |
|--------|---------|----------|--------------|
| `./scripts/init-instance.sh` | First-time setup | None | Generates all secrets, starts containers |
| `./scripts/check-health.sh` | Health check | None | Read-only, validates services & secrets |
| `./scripts/backup.sh` | Database backup | None | Creates SQL dump in `backups/` |
| `./scripts/reset.sh` | Full reset | **Full** | ⚠️ Deletes ALL data, requires re-init |
| `./scripts/rotate-postgres-password.sh` | Rotate DB password | ~30s | Restarts DB-connected services |
| `./scripts/rotate-jwt-secret.sh` | Rotate JWT secret | ~1min | ⚠️ **All user sessions invalidated** |
| `./scripts/rotate-vault-key.sh` | Rotate Vault key | ~1min | ⚠️ **Pooler data reset** |

**Recommended workflow:**
```bash
# 1. Install
./scripts/init-instance.sh

# 2. Verify
./scripts/check-health.sh

# 3. Regular backups
./scripts/backup.sh

# 4. Key rotation (when needed)
./scripts/rotate-postgres-password.sh  # Safe, minimal downtime
./scripts/rotate-jwt-secret.sh         # Users must re-login
./scripts/rotate-vault-key.sh          # Pooler reconfigured
```

For detailed key rotation procedures, see [docs/KEY_ROTATION.md](./docs/KEY_ROTATION.md).

---

## Configuration

Key environment variables (`.env`):

### Secrets (MUST change before first deployment)

| Variable | Description |
|----------|-------------|
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `JWT_SECRET` | JWT signing key (32+ characters) |
| `VAULT_ENC_KEY` | Supavisor encryption key (32+ characters) |
| `ANON_KEY` | Anonymous user JWT token |
| `SERVICE_ROLE_KEY` | Service role JWT token |
| `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` | Studio login credentials |

### Network

| Variable | Default | Description |
|----------|---------|-------------|
| `KONG_HTTP_PORT` | 8000 | API Gateway HTTP port |
| `KONG_HTTPS_PORT` | 8443 | API Gateway HTTPS port |
| `SITE_URL` | http://localhost:3000 | Frontend URL |
| `API_EXTERNAL_URL` | http://localhost:8000 | External API URL |

---

## Maintenance

### Update

```bash
# 1. Check changes
cat CHANGELOG.md

# 2. Pull latest images
docker compose pull

# 3. Restart
docker compose down
docker compose up -d
```

### Backup

```bash
# Backup PostgreSQL data
docker exec supabase-db pg_dumpall -U postgres > backup.sql
```

### Full Reset

```bash
# Delete all data and restart
./scripts/reset.sh
```

---

## Troubleshooting

### Check Service Status

```bash
docker compose ps
docker compose logs <service-name>
```

### Common Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Auth service fails to start | `JWT_SECRET` mismatch | Verify DB and env values match |
| REST API 401 error | Invalid `ANON_KEY`/`SERVICE_ROLE_KEY` | Verify tokens are signed with current `JWT_SECRET` |
| Pooler connection fails | `POSTGRES_PASSWORD` mismatch | Check DB role passwords |
| Studio login fails | `DASHBOARD_PASSWORD` changed | Restart Kong |

---

## Links

- [Self-Hosting Official Documentation](https://supabase.com/docs/guides/self-hosting/docker)
- [GitHub Discussions (Self-Hosted)](https://github.com/orgs/supabase/discussions?discussions_q=is%3Aopen+label%3Aself-hosted)
- [Discord](https://discord.supabase.com)

---

## License

Apache 2.0 - [LICENSE](./LICENSE)
