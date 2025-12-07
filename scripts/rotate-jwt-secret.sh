#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Rotate JWT_SECRET
# ═══════════════════════════════════════════════════════════════════════════════
#
# SCOPE: Development and Staging environments ONLY.
#        For production, use blue/green deployment with new instance instead.
#
# This script:
# 1. Generates a new JWT secret
# 2. Updates DB setting (app.settings.jwt_secret)
# 3. Generates new ANON_KEY and SERVICE_ROLE_KEY
# 4. Updates .env file
# 5. Restarts all services
#
# DESTRUCTIVE: This will invalidate ALL existing user sessions!
#
# Usage:
#   ./scripts/rotate-jwt-secret.sh --dry-run              # Preview only
#   ./scripts/rotate-jwt-secret.sh --allow-destructive    # Execute rotation
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

# ─────────────────────────────────────────────────────────────────────────────
# Generate secrets
# ─────────────────────────────────────────────────────────────────────────────

generate_secret() {
    openssl rand -base64 48 | tr -d '/+=' | head -c 48
}

generate_jwt_token() {
    local role="$1"
    local jwt_secret="$2"
    
    local header='{"alg":"HS256","typ":"JWT"}'
    local header_base64=$(echo -n "$header" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    local iat=$(date +%s)
    local exp=$((iat + 315360000))
    local payload="{\"role\":\"$role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}"
    local payload_base64=$(echo -n "$payload" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    local signature=$(echo -n "${header_base64}.${payload_base64}" | openssl dgst -sha256 -hmac "$jwt_secret" -binary | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    echo "${header_base64}.${payload_base64}.${signature}"
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
    echo "WARNING: This script is intended for DEVELOPMENT/STAGING environments only."
    echo "         For production, use blue/green deployment strategy instead."
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
    echo "  JWT_SECRET Rotation"
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
    log_warn "SCOPE: This script is for DEVELOPMENT/STAGING only."
    log_warn "       For production, deploy a new instance with new secrets"
    log_warn "       and migrate data using blue/green strategy."
    echo ""
    
    # Impact warning
    log_error "DESTRUCTIVE ACTION:"
    log_error "  - ALL existing user sessions will be INVALIDATED"
    log_error "  - ALL users will need to log in again"
    log_error "  - ALL existing JWTs will become invalid"
    echo ""
    
    if ! $DRY_RUN; then
        # Step 1: Offer backup
        log_warn "Step 1/3: Database Backup"
        echo ""
        read -p "Do you want to create a database backup before continuing? [Y/n] " -r backup_ans
        if [[ ! "$backup_ans" =~ ^[Nn]$ ]]; then
            log_info "Creating database backup..."
            if "$SCRIPT_DIR/backup.sh"; then
                log_info "Backup completed successfully."
            else
                log_error "Backup failed! Aborting rotation."
                exit 1
            fi
        else
            log_warn "Skipping backup (not recommended)."
        fi
        echo ""
        
        # Step 2: Confirm understanding
        log_warn "Step 2/3: Confirm Understanding"
        echo ""
        log_info "You are about to rotate JWT_SECRET which will:"
        log_info "  1. Invalidate all existing user sessions"
        log_info "  2. Require all users to log in again"
        log_info "  3. Invalidate all existing API tokens"
        echo ""
        read -p "Type 'rotate-jwt-secret' to confirm: " -r confirm
        if [[ "$confirm" != "rotate-jwt-secret" ]]; then
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
    
    # Get new secret
    local NEW_SECRET="$(generate_secret)"
    local OLD_SECRET=$(get_env_value "JWT_SECRET")
    
    log_info "Current secret: ${OLD_SECRET:0:8}..."
    log_info "New secret: ${NEW_SECRET:0:8}..."
    echo ""
    
    # Generate new JWT tokens
    local NEW_ANON=$(generate_jwt_token "anon" "$NEW_SECRET")
    local NEW_SERVICE=$(generate_jwt_token "service_role" "$NEW_SECRET")
    
    if $DRY_RUN; then
        log_info "[DRY-RUN] Would perform the following actions:"
        echo ""
        log_info "  1. Backup .env file"
        log_info "  2. Update database: ALTER DATABASE postgres SET \"app.settings.jwt_secret\""
        log_info "  3. Update .env:"
        log_info "     - JWT_SECRET=${NEW_SECRET:0:20}..."
        log_info "     - ANON_KEY=${NEW_ANON:0:30}..."
        log_info "     - SERVICE_ROLE_KEY=${NEW_SERVICE:0:30}..."
        log_info "  4. Restart all services (docker compose down && up)"
        echo ""
        log_info "[DRY-RUN] No changes were made."
        exit 0
    fi
    
    # Step 3: Execute
    log_warn "Step 3/3: Executing Rotation"
    echo ""
    
    # Backup .env
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backup created: $ENV_FILE.bak.*"
    
    # Update DB setting
    log_info "Updating database setting..."
    docker exec supabase-db psql -U postgres -c \
        "ALTER DATABASE postgres SET \"app.settings.jwt_secret\" TO '$NEW_SECRET';"
    
    log_info "Database setting updated"
    
    # Update .env file
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$NEW_SECRET|" "$ENV_FILE"
    sed -i "s|^ANON_KEY=.*|ANON_KEY=$NEW_ANON|" "$ENV_FILE"
    sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$NEW_SERVICE|" "$ENV_FILE"
    log_info ".env file updated"
    
    # Restart all services
    log_info "Restarting all services..."
    cd "$PROJECT_ROOT"
    docker compose down
    docker compose up -d
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    log_info "JWT_SECRET rotation complete!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    log_warn "REMINDER: All users must log in again."
    echo ""
    log_info "New keys for your application:"
    log_info "  ANON_KEY: ${NEW_ANON:0:50}..."
    log_info "  SERVICE_ROLE_KEY: ${NEW_SERVICE:0:50}..."
    echo ""
    log_info "Run './scripts/check-health.sh' to verify all services are healthy."
}

main "$@"
