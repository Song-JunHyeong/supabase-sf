#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Supabase Self-Hosted Instance Initialization
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script:
# 1. Detects placeholder secrets in .env
# 2. Generates strong random values for them
# 3. Generates matching ANON_KEY and SERVICE_ROLE_KEY
# 4. Runs first `docker compose up`
#
# Usage: ./scripts/init-instance.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_EXAMPLE="$PROJECT_ROOT/.env.example"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# Read a value from .env file safely (handles spaces)
# ─────────────────────────────────────────────────────────────────────────────

get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Generate random strings
# ─────────────────────────────────────────────────────────────────────────────

generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

generate_secret() {
    openssl rand -base64 48 | tr -d '/+=' | head -c 48
}

generate_jwt_token() {
    local role="$1"
    local jwt_secret="$2"
    
    # JWT Header
    local header='{"alg":"HS256","typ":"JWT"}'
    local header_base64=$(echo -n "$header" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    # JWT Payload (10 year expiry)
    local iat=$(date +%s)
    local exp=$((iat + 315360000))  # 10 years
    local payload="{\"role\":\"$role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}"
    local payload_base64=$(echo -n "$payload" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    # JWT Signature
    local signature=$(echo -n "${header_base64}.${payload_base64}" | openssl dgst -sha256 -hmac "$jwt_secret" -binary | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    echo "${header_base64}.${payload_base64}.${signature}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Check for placeholder values
# ─────────────────────────────────────────────────────────────────────────────

is_placeholder() {
    local value="$1"
    case "$value" in
        "your-"*|"CHANGE"*|"change"*|"placeholder"*|"example"*|"auto-generated"|"")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    log_info "Supabase Self-Hosted Instance Initialization"
    echo ""
    
    # Check if .env exists
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$ENV_EXAMPLE" ]]; then
            log_info "Creating .env from .env.example..."
            cp "$ENV_EXAMPLE" "$ENV_FILE"
        else
            log_error ".env.example not found. Please create .env manually."
            exit 1
        fi
    fi
    
    local updated=false
    local jwt_updated=false
    
    # INSTANCE_NAME is now a fixed default ('supabase') in .env.example
    # Users can manually change it for multi-instance setups
    
    # Generate POSTGRES_PASSWORD if placeholder
    local current_pg_pass=$(get_env_value "POSTGRES_PASSWORD")
    if is_placeholder "$current_pg_pass"; then
        local new_pass=$(generate_password)
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$new_pass|" "$ENV_FILE"
        log_info "Generated new POSTGRES_PASSWORD"
        
        # Clean existing DB data to prevent password mismatch
        # (old DB data would have different password, causing auth failures)
        local db_data_dir="$PROJECT_ROOT/volumes/db/data"
        if [[ -d "$db_data_dir" ]] && [[ "$(ls -A "$db_data_dir" 2>/dev/null)" ]]; then
            log_warn "Cleaning existing DB data to match new password..."
            rm -rf "$db_data_dir"/*
            log_info "DB data cleaned - fresh database will be created"
        fi
        
        updated=true
    fi
    
    # Generate JWT_SECRET if placeholder
    local current_jwt=$(get_env_value "JWT_SECRET")
    if is_placeholder "$current_jwt"; then
        local new_jwt=$(generate_secret)
        sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$new_jwt|" "$ENV_FILE"
        log_info "Generated new JWT_SECRET"
        jwt_updated=true
        updated=true
    fi
    
    # Generate VAULT_ENC_KEY if placeholder
    local current_vault=$(get_env_value "VAULT_ENC_KEY")
    if is_placeholder "$current_vault"; then
        local new_vault=$(generate_password)
        sed -i "s|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=$new_vault|" "$ENV_FILE"
        log_info "Generated new VAULT_ENC_KEY"
        updated=true
    fi
    
    # Generate PG_META_CRYPTO_KEY if placeholder
    local current_meta=$(get_env_value "PG_META_CRYPTO_KEY")
    if is_placeholder "$current_meta"; then
        local new_meta=$(generate_password)
        sed -i "s|^PG_META_CRYPTO_KEY=.*|PG_META_CRYPTO_KEY=$new_meta|" "$ENV_FILE"
        log_info "Generated new PG_META_CRYPTO_KEY"
        updated=true
    fi
    
    # Generate SECRET_KEY_BASE if contains default value
    local current_secret_base=$(get_env_value "SECRET_KEY_BASE")
    if [[ "$current_secret_base" == "UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq" ]]; then
        local new_secret_base=$(generate_secret)
        sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$new_secret_base|" "$ENV_FILE"
        log_info "Generated new SECRET_KEY_BASE"
        updated=true
    fi
    
    # Generate DASHBOARD_PASSWORD if insecure
    local current_dash=$(get_env_value "DASHBOARD_PASSWORD")
    if [[ "$current_dash" == "this_password_is_insecure_and_should_be_updated" ]]; then
        local new_dash=$(generate_password)
        sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$new_dash|" "$ENV_FILE"
        log_info "Generated new DASHBOARD_PASSWORD"
        updated=true
    fi
    
    # Generate POOLER_TENANT_ID if placeholder
    local current_tenant=$(get_env_value "POOLER_TENANT_ID")
    if is_placeholder "$current_tenant"; then
        local new_tenant="tenant-$(openssl rand -hex 4)"
        sed -i "s|^POOLER_TENANT_ID=.*|POOLER_TENANT_ID=$new_tenant|" "$ENV_FILE"
        log_info "Generated new POOLER_TENANT_ID"
        updated=true
    fi
    
    # Regenerate JWT tokens if JWT_SECRET was updated
    if $jwt_updated; then
        local new_jwt_secret=$(get_env_value "JWT_SECRET")
        
        local new_anon=$(generate_jwt_token "anon" "$new_jwt_secret")
        local new_service=$(generate_jwt_token "service_role" "$new_jwt_secret")
        
        sed -i "s|^ANON_KEY=.*|ANON_KEY=$new_anon|" "$ENV_FILE"
        sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$new_service|" "$ENV_FILE"
        log_info "Generated new ANON_KEY and SERVICE_ROLE_KEY"
    fi
    
    # Generate Logflare tokens if placeholders
    local current_lf_pub=$(get_env_value "LOGFLARE_PUBLIC_ACCESS_TOKEN")
    if is_placeholder "$current_lf_pub"; then
        local new_lf_pub=$(generate_secret)
        sed -i "s|^LOGFLARE_PUBLIC_ACCESS_TOKEN=.*|LOGFLARE_PUBLIC_ACCESS_TOKEN=$new_lf_pub|" "$ENV_FILE"
        log_info "Generated new LOGFLARE_PUBLIC_ACCESS_TOKEN"
        updated=true
    fi
    
    local current_lf_priv=$(get_env_value "LOGFLARE_PRIVATE_ACCESS_TOKEN")
    if is_placeholder "$current_lf_priv"; then
        local new_lf_priv=$(generate_secret)
        sed -i "s|^LOGFLARE_PRIVATE_ACCESS_TOKEN=.*|LOGFLARE_PRIVATE_ACCESS_TOKEN=$new_lf_priv|" "$ENV_FILE"
        log_info "Generated new LOGFLARE_PRIVATE_ACCESS_TOKEN"
        updated=true
    fi
    
    echo ""
    
    if $updated; then
        log_info "All secrets have been generated!"
        log_warn "WARNING: These secrets are now IMMUTABLE. See docs/KEY_ROTATION.md for details."
    else
        log_info "All secrets already configured."
    fi
    
    echo ""
    log_info "Starting Supabase..."
    cd "$PROJECT_ROOT"
    docker compose up -d
    
    echo ""
    log_info "Supabase is starting!"
    log_info "Dashboard: http://localhost"
    log_info "Run './scripts/check-health.sh' to verify all services are healthy."
}

main "$@"
