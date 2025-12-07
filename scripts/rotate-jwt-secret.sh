#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Rotate JWT_SECRET
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script:
# 1. Generates a new JWT secret
# 2. Updates DB setting (app.settings.jwt_secret)
# 3. Generates new ANON_KEY and SERVICE_ROLE_KEY
# 4. Updates .env file
# 5. Restarts all services
#
# ⚠️  WARNING: This will invalidate ALL existing user sessions!
#
# Usage: ./scripts/rotate-jwt-secret.sh [new-secret]
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

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    log_info "JWT_SECRET Rotation"
    echo ""
    
    log_warn "⚠️  WARNING: This will invalidate ALL existing user sessions!"
    log_warn "⚠️  All users will need to log in again."
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted."
        exit 0
    fi
    
    # Load current env
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found"
        exit 1
    fi
    source "$ENV_FILE"
    
    # Get new secret
    local NEW_SECRET="${1:-$(generate_secret)}"
    local OLD_SECRET="$JWT_SECRET"
    
    log_info "Current secret: ${OLD_SECRET:0:8}..."
    log_info "New secret: ${NEW_SECRET:0:8}..."
    echo ""
    
    # Backup .env
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Backup created: $ENV_FILE.bak.*"
    
    # Update DB setting
    log_info "Updating database setting..."
    docker exec supabase-db psql -U postgres -c \
        "ALTER DATABASE postgres SET \"app.settings.jwt_secret\" TO '$NEW_SECRET';"
    
    log_info "Database setting updated"
    
    # Generate new JWT tokens
    log_info "Generating new JWT tokens..."
    local NEW_ANON=$(generate_jwt_token "anon" "$NEW_SECRET")
    local NEW_SERVICE=$(generate_jwt_token "service_role" "$NEW_SECRET")
    
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
    log_info "✅ JWT_SECRET rotation complete!"
    log_warn "⚠️  All users must log in again."
    log_info ""
    log_info "New keys for your application:"
    log_info "ANON_KEY: ${NEW_ANON:0:50}..."
    log_info "SERVICE_ROLE_KEY: ${NEW_SERVICE:0:50}..."
    log_info ""
    log_info "Run './scripts/check-health.sh' to verify all services are healthy."
}

main "$@"
