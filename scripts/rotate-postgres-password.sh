#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Rotate POSTGRES_PASSWORD
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script:
# 1. Generates a new password
# 2. Updates all 5 DB roles with the new password
# 3. Updates .env file
# 4. Restarts affected containers
#
# Usage: ./scripts/rotate-postgres-password.sh [new-password]
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

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# Generate password
# ─────────────────────────────────────────────────────────────────────────────

generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    log_info "POSTGRES_PASSWORD Rotation"
    echo ""
    
    # Load current env
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found"
        exit 1
    fi
    # Get new password
    local NEW_PASSWORD="${1:-$(generate_password)}"
    local OLD_PASSWORD=$(get_env_value "POSTGRES_PASSWORD")
    
    log_info "Current password: ${OLD_PASSWORD:0:4}...${OLD_PASSWORD: -4}"
    log_info "New password: ${NEW_PASSWORD:0:4}...${NEW_PASSWORD: -4}"
    echo ""
    
    # Backup .env
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backup created: $ENV_FILE.bak.*"
    
    # Update all DB roles
    log_info "Updating database roles..."
    
    docker exec supabase-db psql -U postgres -c "ALTER USER authenticator WITH PASSWORD '$NEW_PASSWORD';"
    docker exec supabase-db psql -U postgres -c "ALTER USER pgbouncer WITH PASSWORD '$NEW_PASSWORD';"
    docker exec supabase-db psql -U postgres -c "ALTER USER supabase_auth_admin WITH PASSWORD '$NEW_PASSWORD';"
    docker exec supabase-db psql -U postgres -c "ALTER USER supabase_functions_admin WITH PASSWORD '$NEW_PASSWORD';"
    docker exec supabase-db psql -U postgres -c "ALTER USER supabase_storage_admin WITH PASSWORD '$NEW_PASSWORD';"
    
    log_info "Database roles updated"
    
    # Update .env file
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$NEW_PASSWORD|" "$ENV_FILE"
    log_info ".env file updated"
    
    # Restart affected services
    log_info "Restarting services..."
    cd "$PROJECT_ROOT"
    docker compose restart auth rest storage meta functions supavisor realtime
    
    echo ""
    log_info "✅ POSTGRES_PASSWORD rotation complete!"
    log_info "Run './scripts/check-health.sh' to verify all services are healthy."
}

main "$@"
