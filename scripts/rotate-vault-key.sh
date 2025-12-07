#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Rotate VAULT_ENC_KEY
# ═══════════════════════════════════════════════════════════════════════════════
#
# ⚠️  CRITICAL WARNING: This requires a FULL RESET of Supavisor data!
#
# The VAULT_ENC_KEY is used by Supavisor to encrypt tenant data.
# Changing it means all encrypted data becomes unreadable.
#
# This script will:
# 1. Stop all services
# 2. Clear Supavisor encrypted data
# 3. Generate new VAULT_ENC_KEY
# 4. Restart everything
#
# Usage: ./scripts/rotate-vault-key.sh
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

generate_key() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    log_error "═══════════════════════════════════════════════════════════════"
    log_error "⚠️  CRITICAL: VAULT_ENC_KEY Rotation"
    log_error "═══════════════════════════════════════════════════════════════"
    echo ""
    log_warn "This operation will:"
    log_warn "  1. Stop ALL Supabase services"
    log_warn "  2. Clear Supavisor's encrypted tenant data"
    log_warn "  3. Generate a new VAULT_ENC_KEY"
    log_warn "  4. Reinitialize Supavisor"
    echo ""
    log_warn "⚠️  Connection pooler configuration will be RESET!"
    log_warn "⚠️  You may need to reconfigure pooler settings."
    echo ""
    
    read -p "Are you ABSOLUTELY sure? Type 'ROTATE' to confirm: " -r
    echo
    if [[ "$REPLY" != "ROTATE" ]]; then
        log_info "Aborted."
        exit 0
    fi
    
    # Load current env
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found"
        exit 1
    fi
    source "$ENV_FILE"
    
    # Backup
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backup created: $ENV_FILE.bak.*"
    
    # Generate new key
    local NEW_KEY=$(generate_key)
    log_info "New VAULT_ENC_KEY: ${NEW_KEY:0:8}..."
    
    # Stop all services
    log_info "Stopping all services..."
    cd "$PROJECT_ROOT"
    docker compose down
    
    # Clear Supavisor data from DB
    log_info "Starting database only..."
    docker compose up -d db
    sleep 10
    
    log_info "Clearing Supavisor data..."
    docker exec supabase-db psql -U postgres -d _supabase -c "TRUNCATE TABLE supavisor.tenants CASCADE;" 2>/dev/null || true
    
    # Update .env
    sed -i "s|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=$NEW_KEY|" "$ENV_FILE"
    log_info ".env file updated"
    
    # Restart everything
    log_info "Starting all services..."
    docker compose up -d
    
    echo ""
    log_info "✅ VAULT_ENC_KEY rotation complete!"
    log_warn "⚠️  The connection pooler has been reinitialized."
    log_info "Run './scripts/check-health.sh' to verify all services are healthy."
}

main "$@"
