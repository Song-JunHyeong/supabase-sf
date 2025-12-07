#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Supabase Health Check
# ═══════════════════════════════════════════════════════════════════════════════
#
# Checks:
# 1. All container health status
# 2. Service-specific endpoint checks
# 3. Secret mismatch detection (env vs DB)
#
# Usage: ./scripts/check-health.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok() { echo -e "${GREEN}✅${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
log_fail() { echo -e "${RED}❌${NC} $1"; }

get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

ERRORS=0

# ─────────────────────────────────────────────────────────────────────────────
# Container Health Checks
# ─────────────────────────────────────────────────────────────────────────────

check_container() {
    local name="$1"
    local status=$(docker inspect --format='{{.State.Health.Status}}' "$name" 2>/dev/null || echo "not_found")
    
    case "$status" in
        "healthy")
            log_ok "$name: healthy"
            ;;
        "starting")
            log_warn "$name: starting (please wait)"
            ;;
        "unhealthy")
            log_fail "$name: unhealthy"
            ERRORS=$((ERRORS + 1))
            ;;
        "not_found")
            log_warn "$name: container not found"
            ;;
        *)
            # Container running but no healthcheck defined
            local running=$(docker inspect --format='{{.State.Running}}' "$name" 2>/dev/null || echo "false")
            if [[ "$running" == "true" ]]; then
                log_ok "$name: running (no healthcheck)"
            else
                log_fail "$name: not running"
                ERRORS=$((ERRORS + 1))
            fi
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Endpoint Checks
# ─────────────────────────────────────────────────────────────────────────────

check_endpoint() {
    local name="$1"
    local url="$2"
    
    if curl -sf -o /dev/null --max-time 5 "$url"; then
        log_ok "$name endpoint: OK"
    else
        log_fail "$name endpoint: FAILED ($url)"
        ERRORS=$((ERRORS + 1))
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Secret Mismatch Detection
# ─────────────────────────────────────────────────────────────────────────────

check_secret_sync() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_warn "Cannot check secret sync: .env not found"
        return
    fi
    
    local JWT_SECRET=$(get_env_value "JWT_SECRET")
    
    # Check JWT_SECRET matches DB
    local db_jwt=$(docker exec supabase-db psql -U postgres -t -c \
        "SHOW \"app.settings.jwt_secret\";" 2>/dev/null | tr -d ' \n' || echo "")
    
    if [[ -z "$db_jwt" ]]; then
        log_warn "Could not read JWT_SECRET from DB"
    elif [[ "$db_jwt" == "$JWT_SECRET" ]]; then
        log_ok "JWT_SECRET: env and DB match"
    else
        log_fail "JWT_SECRET MISMATCH: env and DB values differ!"
        log_fail "  This will cause authentication failures."
        log_fail "  See docs/KEY_ROTATION.md for recovery steps."
        ERRORS=$((ERRORS + 1))
    fi
    
    # Check POSTGRES_PASSWORD by attempting connection
    if docker exec supabase-db psql -U authenticator -h localhost -c "SELECT 1;" >/dev/null 2>&1; then
        log_ok "POSTGRES_PASSWORD: authenticator role can connect"
    else
        log_warn "POSTGRES_PASSWORD: could not verify (role may not have login)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Supabase Self-Hosted Health Check"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    echo "📦 Container Status"
    echo "───────────────────────────────────────────────────────────────"
    check_container "supabase-db"
    check_container "supabase-kong"
    check_container "supabase-auth"
    check_container "supabase-rest"
    check_container "realtime-dev.supabase-realtime"
    check_container "supabase-storage"
    check_container "supabase-meta"
    check_container "supabase-edge-functions"
    check_container "supabase-pooler"
    check_container "supabase-studio"
    
    # Optional services
    check_container "supabase-analytics"
    check_container "supabase-imgproxy"
    check_container "supabase-vector"
    
    echo ""
    echo "🌐 Endpoint Checks"
    echo "───────────────────────────────────────────────────────────────"
    check_endpoint "Kong Gateway" "http://localhost:8000"
    check_endpoint "Auth" "http://localhost:8000/auth/v1/health"
    check_endpoint "REST" "http://localhost:8000/rest/v1/"
    check_endpoint "Storage" "http://localhost:8000/storage/v1/status"
    
    echo ""
    echo "🔑 Secret Synchronization"
    echo "───────────────────────────────────────────────────────────────"
    check_secret_sync
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    if [[ $ERRORS -eq 0 ]]; then
        log_ok "All checks passed!"
        exit 0
    else
        log_fail "$ERRORS check(s) failed"
        exit 1
    fi
}

main "$@"
