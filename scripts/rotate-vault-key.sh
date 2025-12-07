#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Rotate VAULT_ENC_KEY
# ═══════════════════════════════════════════════════════════════════════════════
#
# SCOPE: Development and Staging environments ONLY.
#        For production, deploy a new instance with new keys instead.
#
# CRITICAL WARNING: This DESTROYS all Vault-encrypted data!
# 
# The VAULT_ENC_KEY is used by Supavisor to encrypt tenant data.
# Changing it means ALL encrypted data becomes PERMANENTLY UNREADABLE.
#
# Only use if:
#   - Vault data is "regeneratable" (can be recreated from external sources)
#   - You are willing to lose all pooler configuration
#   - This is NOT a production environment
#
# Usage:
#   ./scripts/rotate-vault-key.sh --dry-run              # Preview only
#   ./scripts/rotate-vault-key.sh --allow-destructive    # Execute rotation
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

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

generate_key() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run              Preview what would happen (no changes)"
    echo "  --allow-destructive    Execute the rotation (required for actual changes)"
    echo "  --help                 Show this help"
    echo ""
    echo "CRITICAL: This script DESTROYS Vault-encrypted data!"
    echo "          Only use for DEVELOPMENT/STAGING environments."
    echo "          For production, deploy a new instance instead."
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
    log_error "  CRITICAL: VAULT_ENC_KEY Rotation"
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
    
    # Scope warning
    log_error "SCOPE: This script is for DEVELOPMENT/STAGING only."
    log_error "       NEVER use in production!"
    log_error "       For production, deploy a new instance with new secrets."
    echo ""
    
    # What will be destroyed
    log_error "DATA DESTRUCTION WARNING:"
    log_error "========================================="
    log_error "  The following will be PERMANENTLY LOST:"
    log_error "    - ALL Supavisor encrypted tenant data"
    log_error "    - ALL connection pooler configuration"
    log_error "    - ANY secrets stored in Vault"
    log_error ""
    log_error "  This data CANNOT be recovered after key rotation."
    log_error "  Only proceed if this data is REGENERATABLE."
    log_error "========================================="
    echo ""
    
    # Impact details
    log_warn "This operation will:"
    log_warn "  1. Stop ALL Supabase services"
    log_warn "  2. TRUNCATE Supavisor tenant tables (data loss)"
    log_warn "  3. Generate a new VAULT_ENC_KEY"
    log_warn "  4. Reinitialize Supavisor from scratch"
    echo ""
    
    if ! $DRY_RUN; then
        # Step 1: Offer backup
        log_warn "Step 1/4: Database Backup"
        echo ""
        read -p "Do you want to create a database backup before continuing? [Y/n] " -r backup_ans
        if [[ ! "$backup_ans" =~ ^[Nn]$ ]]; then
            log_info "Creating database backup..."
            if "$SCRIPT_DIR/backup.sh"; then
                log_info "Backup completed."
                log_warn "Note: Vault data in backup will NOT be readable with new key."
            else
                log_error "Backup failed! Aborting rotation."
                exit 1
            fi
        else
            log_warn "Skipping backup (NOT RECOMMENDED)."
        fi
        echo ""
        
        # Step 2: Confirm data loss understanding
        log_warn "Step 2/4: Confirm Data Loss Understanding"
        echo ""
        log_error "You are about to DESTROY Vault-encrypted data."
        log_error "This action is IRREVERSIBLE."
        echo ""
        read -p "Do you understand that Vault data will be PERMANENTLY LOST? [y/N] " -r understand
        if [[ ! "$understand" =~ ^[Yy]$ ]]; then
            log_info "Aborted."
            exit 0
        fi
        echo ""
        
        # Step 3: Confirm data is regeneratable
        log_warn "Step 3/4: Confirm Data Regeneratability"
        echo ""
        read -p "Is ALL Vault-stored data regeneratable from external sources? [y/N] " -r regen
        if [[ ! "$regen" =~ ^[Yy]$ ]]; then
            log_error "Do NOT proceed if data is not regeneratable!"
            log_error "Aborted for safety."
            exit 1
        fi
        echo ""
        
        # Step 4: Final confirmation with scary keyword
        log_warn "Step 4/4: Final Confirmation"
        echo ""
        read -p "Type 'destroy-vault-data' to confirm: " -r confirm
        if [[ "$confirm" != "destroy-vault-data" ]]; then
            log_info "Aborted."
            exit 0
        fi
        echo ""
    fi
    
    # Load current env
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found"
        exit 1
    fi
    
    # Generate new key
    local NEW_KEY=$(generate_key)
    local OLD_KEY=$(grep "^VAULT_ENC_KEY=" "$ENV_FILE" | cut -d'=' -f2- | head -1)
    
    log_info "Current key: ${OLD_KEY:0:8}..."
    log_info "New key: ${NEW_KEY:0:8}..."
    echo ""
    
    if $DRY_RUN; then
        log_info "[DRY-RUN] Would perform the following actions:"
        echo ""
        log_info "  1. Backup .env file"
        log_info "  2. Stop all services (docker compose down)"
        log_info "  3. Start database only"
        log_info "  4. Execute: TRUNCATE TABLE supavisor.tenants CASCADE"
        log_info "  5. Update .env: VAULT_ENC_KEY=${NEW_KEY:0:10}..."
        log_info "  6. Restart all services (docker compose up -d)"
        echo ""
        log_info "[DRY-RUN] No changes were made."
        exit 0
    fi
    
    # Execute rotation
    log_info "Executing VAULT_ENC_KEY rotation..."
    echo ""
    
    # Backup
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backup created: $ENV_FILE.bak.*"
    
    # Stop all services
    log_info "Stopping all services..."
    cd "$PROJECT_ROOT"
    docker compose down
    
    # Clear Supavisor data from DB
    log_info "Starting database only..."
    docker compose up -d db
    sleep 10
    
    log_info "Clearing Supavisor data (DESTRUCTIVE)..."
    local db_container="$(get_instance_name)-db"
    docker exec "$db_container" psql -U postgres -d _supabase -c "TRUNCATE TABLE supavisor.tenants CASCADE;" 2>/dev/null || true
    
    # Update .env
    sed -i "s|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=$NEW_KEY|" "$ENV_FILE"
    log_info ".env file updated"
    
    # Restart everything
    log_info "Starting all services..."
    docker compose up -d
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    log_info "VAULT_ENC_KEY rotation complete!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    log_warn "REMINDER: Connection pooler has been reinitialized."
    log_warn "          You may need to reconfigure pooler settings."
    echo ""
    log_info "Run './scripts/check-health.sh' to verify all services are healthy."
}

main "$@"
