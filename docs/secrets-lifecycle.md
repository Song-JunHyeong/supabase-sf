# Secrets Lifecycle Guide

This document covers the complete lifecycle of Supabase secrets: initialization, rotation, and recovery.

## Overview

| Secret | Location | Rotation Script | Impact |
|--------|----------|-----------------|--------|
| `POSTGRES_PASSWORD` | 5 DB roles | `rotate-postgres-password.sh` | ~30s downtime |
| `JWT_SECRET` | DB settings + tokens | `rotate-jwt-secret.sh` | All sessions invalidated |
| `VAULT_ENC_KEY` | Supavisor encryption | `rotate-vault-key.sh` | Pooler data reset |

---

## Test Scenarios

### Scenario 1: Rotate POSTGRES_PASSWORD

**Prerequisites**: Running instance with some data

```bash
# 1. Create test data
docker exec supabase-db psql -U postgres -c "CREATE TABLE test_data (id serial, name text);"
docker exec supabase-db psql -U postgres -c "INSERT INTO test_data (name) VALUES ('before_rotation');"

# 2. Rotate password
./scripts/rotate-postgres-password.sh

# 3. Verify data preserved
docker exec supabase-db psql -U postgres -c "SELECT * FROM test_data;"
# Expected: Row with 'before_rotation' still exists

# 4. Verify services work
./scripts/check-health.sh
# Expected: All services healthy

# 5. Test API access
curl http://localhost:8000/rest/v1/test_data -H "apikey: $ANON_KEY"
# Expected: JSON response with data
```

**What happens:**
- Password updated in 5 DB roles
- `.env` file updated
- Services restarted (auth, rest, storage, meta, functions, supavisor, realtime)
- **Data is preserved**
- **Existing connections may drop briefly**

---

### Scenario 2: Rotate JWT_SECRET

**Prerequisites**: Running instance with authenticated users

```bash
# 1. Get current ANON_KEY
OLD_ANON_KEY=$(grep "^ANON_KEY=" .env | cut -d'=' -f2)

# 2. Create a user and get token
curl -X POST http://localhost:8000/auth/v1/signup \
  -H "apikey: $OLD_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpassword123"}'

# 3. Rotate JWT secret
./scripts/rotate-jwt-secret.sh

# 4. Get new ANON_KEY
NEW_ANON_KEY=$(grep "^ANON_KEY=" .env | cut -d'=' -f2)

# 5. Verify OLD token fails
curl http://localhost:8000/rest/v1/ -H "apikey: $OLD_ANON_KEY"
# Expected: 401 Unauthorized

# 6. Verify NEW token works
curl http://localhost:8000/rest/v1/ -H "apikey: $NEW_ANON_KEY"
# Expected: 200 OK

# 7. User must re-login
curl -X POST http://localhost:8000/auth/v1/token?grant_type=password \
  -H "apikey: $NEW_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpassword123"}'
# Expected: New access token issued
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
> This is the most destructive rotation. Only use when absolutely necessary.

```bash
# 1. Note current pooler settings
docker exec supabase-db psql -U postgres -d _supabase \
  -c "SELECT * FROM supavisor.tenants;" 2>/dev/null

# 2. Rotate vault key (type 'ROTATE' to confirm)
./scripts/rotate-vault-key.sh

# 3. Verify pooler reinitialized
docker exec supabase-db psql -U postgres -d _supabase \
  -c "SELECT * FROM supavisor.tenants;" 2>/dev/null
# Expected: Fresh tenant configuration

# 4. Verify connection pooling works
psql "postgres://postgres.your-tenant-id:password@localhost:6543/postgres" -c "SELECT 1;"
```

**What happens:**
- All services stopped
- Supavisor tenant data truncated
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

---

## Best Practices

1. **Always backup before rotation**
   ```bash
   ./scripts/backup.sh
   ```

2. **Test in staging first**

3. **Notify users before JWT rotation** (they'll be logged out)

4. **Schedule rotations during low-traffic periods**

5. **Keep backup .env files secure** (they contain previous secrets)
