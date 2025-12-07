# Secrets Lifecycle Guide

This document covers the complete lifecycle of Supabase secrets: initialization, rotation, and recovery.

> [!IMPORTANT]
> **SCOPE LIMITATION**: The rotation scripts (`rotate-*.sh`) are designed for **DEVELOPMENT and STAGING environments ONLY**.
> For production environments, use a blue/green deployment strategy with a new instance instead.

---

## Environment-Specific Guidance

### Development Environment

- **Purpose**: Testing, experimentation, rapid iteration
- **Data sensitivity**: Low (mock/test data)
- **Rotation scripts**: Safe to use freely
- **Recovery priority**: Low

```bash
# Development: Use rotation scripts freely
./scripts/rotate-jwt-secret.sh --allow-destructive
./scripts/rotate-vault-key.sh --allow-destructive
```

### Staging Environment

- **Purpose**: Production-like testing before deployment
- **Data sensitivity**: Medium (realistic but not real user data)
- **Rotation scripts**: Use with backups
- **Recovery priority**: Medium

```bash
# Staging: Always backup first
./scripts/backup.sh
./scripts/rotate-jwt-secret.sh --allow-destructive
```

### Production Environment

- **Purpose**: Real users, real data
- **Data sensitivity**: HIGH
- **Rotation scripts**: NOT RECOMMENDED
- **Recovery priority**: CRITICAL

> [!CAUTION]
> **DO NOT use rotation scripts in production.**
> Instead, use the blue/green deployment strategy:

1. **Deploy new instance** with fresh secrets
2. **Migrate data** from old instance to new
3. **Update DNS/load balancer** to point to new instance
4. **Decommission old instance** after verification

This approach ensures:
- Zero data loss
- Minimal downtime
- Rollback capability
- Audit trail

---

## Overview

| Secret | Location | Rotation Script | Impact | Production Strategy |
|--------|----------|-----------------|--------|---------------------|
| `POSTGRES_PASSWORD` | 5 DB roles | `rotate-postgres-password.sh` | ~30s downtime | Blue/green deployment |
| `JWT_SECRET` | DB settings + tokens | `rotate-jwt-secret.sh` | All sessions invalidated | Blue/green deployment |
| `VAULT_ENC_KEY` | Supavisor encryption | `rotate-vault-key.sh` | Pooler data DESTROYED | Blue/green deployment |

---

## Script Usage

### Common Options

All rotation scripts support:

```bash
--dry-run              # Preview what would happen (no changes made)
--allow-destructive    # Execute the actual rotation
--help                 # Show usage information
```

### Recommended Workflow

```bash
# 1. Always preview first
./scripts/rotate-jwt-secret.sh --dry-run

# 2. Create backup
./scripts/backup.sh

# 3. Execute rotation (only if dry-run looks correct)
./scripts/rotate-jwt-secret.sh --allow-destructive
```

---

## Test Scenarios

### Scenario 1: Rotate POSTGRES_PASSWORD

**Prerequisites**: Running instance with some data

```bash
# 1. Create test data
docker exec supabase-db psql -U postgres -c "CREATE TABLE test_data (id serial, name text);"
docker exec supabase-db psql -U postgres -c "INSERT INTO test_data (name) VALUES ('before_rotation');"

# 2. Preview rotation
./scripts/rotate-postgres-password.sh --dry-run

# 3. Rotate password
./scripts/rotate-postgres-password.sh --allow-destructive

# 4. Verify data preserved
docker exec supabase-db psql -U postgres -c "SELECT * FROM test_data;"
# Expected: Row with 'before_rotation' still exists

# 5. Verify services work
./scripts/check-health.sh
```

**What happens:**
- Password updated in 5 DB roles
- `.env` file updated
- Services restarted
- **Data is preserved**
- **Existing connections may drop briefly**

---

### Scenario 2: Rotate JWT_SECRET

**Prerequisites**: Running instance with authenticated users

```bash
# 1. Preview rotation
./scripts/rotate-jwt-secret.sh --dry-run

# 2. Get current ANON_KEY for comparison
OLD_ANON_KEY=$(grep "^ANON_KEY=" .env | cut -d'=' -f2)

# 3. Rotate JWT secret (will prompt for backup and confirmation)
./scripts/rotate-jwt-secret.sh --allow-destructive

# 4. Get new ANON_KEY
NEW_ANON_KEY=$(grep "^ANON_KEY=" .env | cut -d'=' -f2)

# 5. Verify OLD token fails
curl http://localhost:8000/rest/v1/ -H "apikey: $OLD_ANON_KEY"
# Expected: 401 Unauthorized

# 6. Verify NEW token works
curl http://localhost:8000/rest/v1/ -H "apikey: $NEW_ANON_KEY"
# Expected: 200 OK
```

**What happens:**
- New JWT_SECRET generated
- DB setting `app.settings.jwt_secret` updated
- New ANON_KEY and SERVICE_ROLE_KEY generated
- **All existing tokens invalidated**
- **All users must log in again**
- **User data is preserved**

---

### Scenario 3: Rotate VAULT_ENC_KEY

> [!CAUTION]
> **DESTRUCTIVE OPERATION**: This permanently destroys Vault-encrypted data.
> Only use if the encrypted data is regeneratable from external sources.

```bash
# 1. Preview rotation
./scripts/rotate-vault-key.sh --dry-run

# 2. Note current pooler settings (will be lost)
docker exec supabase-db psql -U postgres -d _supabase \
  -c "SELECT * FROM supavisor.tenants;" 2>/dev/null

# 3. Rotate vault key (requires 4-step confirmation)
./scripts/rotate-vault-key.sh --allow-destructive
# - Step 1: Offer backup
# - Step 2: Confirm data loss understanding
# - Step 3: Confirm data is regeneratable
# - Step 4: Type 'destroy-vault-data' to confirm

# 4. Verify pooler reinitialized
./scripts/check-health.sh
```

**What happens:**
- All services stopped
- Supavisor tenant data **TRUNCATED (permanent data loss)**
- New VAULT_ENC_KEY generated
- Supavisor reinitialized with fresh config
- **Connection pooler settings reset**
- **Database data is preserved**

---

## Recovery Procedures

### If rotation fails mid-way

1. Check backup files:
   ```bash
   ls -la .env.bak.*
   ```

2. Restore from backup:
   ```bash
   cp .env.bak.YYYYMMDDHHMMSS .env
   docker compose down
   docker compose up -d
   ```

### If secrets mismatch detected

```bash
# Check current state
./scripts/check-health.sh

# If JWT mismatch, verify DB setting
docker exec supabase-db psql -U postgres -c "SHOW \"app.settings.jwt_secret\";"

# Compare with .env
grep "^JWT_SECRET=" .env
```

### Restore from database backup

```bash
# If you need to restore data
docker compose down
docker compose up -d db
docker exec -i supabase-db psql -U postgres < backups/backup_YYYYMMDD_HHMMSS.sql
docker compose up -d
```

---

## Best Practices

1. **Always use --dry-run first**
   ```bash
   ./scripts/rotate-jwt-secret.sh --dry-run
   ```

2. **Always backup before rotation**
   ```bash
   ./scripts/backup.sh
   ```

3. **Test in staging first** before considering production

4. **Notify users before JWT rotation** (they'll be logged out)

5. **Schedule rotations during low-traffic periods**

6. **Keep backup .env files secure** (they contain previous secrets)

7. **Never use rotation scripts in production** - use blue/green deployment

---

## Production: Blue/Green Deployment Strategy

For production environments, follow this strategy instead of using rotation scripts:

### Step 1: Deploy New Instance

```bash
# On a new server or in a new directory
git clone https://github.com/YOUR_REPO/supabase-sf.git supabase-new
cd supabase-new
./scripts/init-instance.sh  # Generates fresh secrets
```

### Step 2: Migrate Data

```bash
# On old instance
./scripts/backup.sh

# Copy backup to new instance
scp backups/backup_*.sql new-server:/path/to/supabase-new/

# On new instance
docker exec -i supabase-db psql -U postgres < backup_*.sql
```

### Step 3: Update Application Config

Update your application's environment variables:
- `SUPABASE_URL` → New instance URL
- `SUPABASE_ANON_KEY` → New instance's ANON_KEY
- `SUPABASE_SERVICE_ROLE_KEY` → New instance's SERVICE_ROLE_KEY

### Step 4: Switch Traffic

Update DNS or load balancer to point to new instance.

### Step 5: Verify and Decommission

- Verify new instance is working correctly
- Keep old instance running for rollback (24-48 hours)
- Decommission old instance after verification period
