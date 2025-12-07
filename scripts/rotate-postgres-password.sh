#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Rotate POSTGRES_PASSWORD
# ═══════════════════════════════════════════════════════════════════════════════
#
# SCOPE: Development and Staging environments.
#        For production, consider blue/green deployment with new instance.
#
# This script:
# 1. Generates a new password
# 2. Updates all 5 DB roles with the new password
# 3. Updates .env file
# 4. Restarts affected containers
#
# Impact: ~30s downtime, existing connections may drop
# Data: PRESERVED (no data loss)
#
# Usage:
#   ./scripts/rotate-postgres-password.sh --dry-run              # Preview only
#   ./scripts/rotate-postgres-password.sh --allow-destructive    # Execute rotation
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Mode flags
DRY_RUN=false
ALLOW_DESTRUCTIVE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run              Preview what would happen (no changes)"
    echo "  --allow-destructive    Execute the rotation (required for actual changes)"
    echo "  --help                 Show this help"
    echo ""
    echo "This is the safest rotation script - it preserves all data."
    echo "Impact: ~30s downtime, existing connections may drop temporarily."
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --allow-destructive)
                ALLOW_DESTRUCTIVE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  POSTGRES_PASSWORD Rotation"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if $DRY_RUN; then
        log_info "[DRY-RUN MODE] No changes will be made."
        echo ""
    fi
    
    # Check flags
    if ! $DRY_RUN && ! $ALLOW_DESTRUCTIVE; then
        log_error "You must specify either --dry-run or --allow-destructive"
        echo ""
        show_usage
        exit 1
    fi
    
    # Impact info
    log_info "IMPACT:"
    log_info "  - Brief downtime (~30 seconds)"
    log_info "  - Existing database connections will drop"
    log_info "  - All data is PRESERVED"
    echo ""
    
    log_warn "Affected components:"
    log_warn "  - 5 DB roles (authenticator, pgbouncer, supabase_auth_admin, etc.)"
    log_warn "  - Services: auth, rest, storage, meta, functions, supavisor, realtime"
    echo ""
    
    # Load current env
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found"
        exit 1
    fi
    
    # Get passwords
    local NEW_PASSWORD="$(generate_password)"
    local OLD_PASSWORD=$(get_env_value "POSTGRES_PASSWORD")
    
    log_info "Current password: ${OLD_PASSWORD:0:4}...${OLD_PASSWORD: -4}"
    log_info "New password: ${NEW_PASSWORD:0:4}...${NEW_PASSWORD: -4}"
    echo ""
    
    if $DRY_RUN; then
        log_info "[DRY-RUN] Would perform the following actions:"
        echo ""
        log_info "  1. Backup .env file"
        log_info "  2. Update DB role: authenticator"
        log_info "  3. Update DB role: pgbouncer"
        log_info "  4. Update DB role: supabase_auth_admin"
        log_info "  5. Update DB role: supabase_functions_admin"
        log_info "  6. Update DB role: supabase_storage_admin"
        log_info "  7. Update .env: POSTGRES_PASSWORD=****"
        log_info "  8. Restart: auth, rest, storage, meta, functions, supavisor, realtime"
        echo ""
        log_info "[DRY-RUN] No changes were made."
        exit 0
    fi
    
    # Offer backup
    read -p "Do you want to create a database backup before continuing? [Y/n] " -r backup_ans
    if [[ ! "$backup_ans" =~ ^[Nn]$ ]]; then
        log_info "Creating database backup..."
        if "$SCRIPT_DIR/backup.sh"; then
            log_info "Backup completed successfully."
        else
            log_error "Backup failed! Aborting rotation."
            exit 1
        fi
    fi
    echo ""
    
    # Confirm
    read -p "Proceed with password rotation? [y/N] " -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Aborted."
        exit 0
    fi
    echo ""
    
    # Execute
    log_info "Executing password rotation..."
    
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
    echo "═══════════════════════════════════════════════════════════════"
    log_info "POSTGRES_PASSWORD rotation complete!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    log_info "Run './scripts/check-health.sh' to verify all services are healthy."
}

main "$@"
