#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Supabase Auto-Init Entrypoint
# ═══════════════════════════════════════════════════════════════════════════════
#
# This script runs automatically on first container start.
# If secrets are not yet configured, it generates them and updates .env
#
# Works automatically with any Docker deployment tool:
# - docker compose up -d
# - EasyPanel, Portainer, Coolify, Kubernetes, etc.
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

ENV_FILE="/app/.env"
ENV_EXAMPLE="/app/.env.example"
INIT_MARKER="/app/.initialized"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INIT]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Generate secure random password (32 chars)
generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

# Generate secure random secret (48 chars)
generate_secret() {
    openssl rand -base64 48 | tr -d '/+=' | head -c 48
}

# Generate JWT token
generate_jwt_token() {
    local role="$1"
    local secret="$2"
    
    local header='{"alg":"HS256","typ":"JWT"}'
    local now=$(date +%s)
    local exp=$((now + 315360000))  # 10 years
    local payload="{\"role\":\"$role\",\"iss\":\"supabase-self-host\",\"iat\":$now,\"exp\":$exp}"
    
    local header_b64=$(echo -n "$header" | openssl base64 -e | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    local payload_b64=$(echo -n "$payload" | openssl base64 -e | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    local signature=$(echo -n "${header_b64}.${payload_b64}" | openssl dgst -sha256 -hmac "$secret" -binary | openssl base64 -e | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    echo "${header_b64}.${payload_b64}.${signature}"
}

# Check if value is a placeholder
is_placeholder() {
    local value="$1"
    [[ "$value" == your-* ]] || [[ "$value" == *"super-secret"* ]] || [[ -z "$value" ]]
}

# Get env value
get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

# Main initialization
main() {
    log_info "Supabase Auto-Initialization Check"
    
    # Check if already initialized
    if [[ -f "$INIT_MARKER" ]]; then
        log_info "Already initialized."
        # Still print env info for deploy terminal
        print_env_info
        print_mcp_guide
        exit 0
    fi
    
    # Create .env from example if not exists
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$ENV_EXAMPLE" ]]; then
            log_info "Creating .env from .env.example..."
            cp "$ENV_EXAMPLE" "$ENV_FILE"
        else
            log_error ".env.example not found!"
            exit 1
        fi
    fi
    
    local updated=false
    local jwt_updated=false
    
    # Generate unique INSTANCE_NAME if default
    local instance=$(get_env_value "INSTANCE_NAME")
    if [[ "$instance" == "supabase" ]] || [[ -z "$instance" ]]; then
        # Generate short unique ID (6 chars)
        local unique_id=$(openssl rand -hex 3)
        local new_instance="supabase-${unique_id}"
        sed -i "s|^INSTANCE_NAME=.*|INSTANCE_NAME=$new_instance|" "$ENV_FILE"
        log_info "Generated INSTANCE_NAME: $new_instance"
        updated=true
    fi
    
    # Generate POSTGRES_PASSWORD
    local pg_pass=$(get_env_value "POSTGRES_PASSWORD")
    if is_placeholder "$pg_pass"; then
        local new_pass=$(generate_password)
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$new_pass|" "$ENV_FILE"
        log_info "Generated POSTGRES_PASSWORD"
        updated=true
    fi
    
    # Generate JWT_SECRET
    local jwt=$(get_env_value "JWT_SECRET")
    if is_placeholder "$jwt"; then
        local new_jwt=$(generate_secret)
        sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$new_jwt|" "$ENV_FILE"
        log_info "Generated JWT_SECRET"
        jwt_updated=true
        updated=true
    fi
    
    # Generate VAULT_ENC_KEY
    local vault=$(get_env_value "VAULT_ENC_KEY")
    if is_placeholder "$vault"; then
        local new_vault=$(generate_password)
        sed -i "s|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=$new_vault|" "$ENV_FILE"
        log_info "Generated VAULT_ENC_KEY"
        updated=true
    fi
    
    # Generate PG_META_CRYPTO_KEY
    local meta=$(get_env_value "PG_META_CRYPTO_KEY")
    if is_placeholder "$meta"; then
        local new_meta=$(generate_password)
        sed -i "s|^PG_META_CRYPTO_KEY=.*|PG_META_CRYPTO_KEY=$new_meta|" "$ENV_FILE"
        log_info "Generated PG_META_CRYPTO_KEY"
        updated=true
    fi
    
    # Generate SECRET_KEY_BASE
    local secret_base=$(get_env_value "SECRET_KEY_BASE")
    if [[ "$secret_base" == "UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq" ]] || is_placeholder "$secret_base"; then
        local new_secret=$(generate_secret)
        sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$new_secret|" "$ENV_FILE"
        log_info "Generated SECRET_KEY_BASE"
        updated=true
    fi
    
    # Generate DASHBOARD_PASSWORD
    local dash=$(get_env_value "DASHBOARD_PASSWORD")
    if [[ -z "$dash" ]] || [[ "$dash" == "this_password_is_insecure_and_should_be_updated" ]] || is_placeholder "$dash"; then
        local new_dash=$(generate_password)
        sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$new_dash|" "$ENV_FILE"
        log_info "Generated DASHBOARD_PASSWORD"
        updated=true
    fi
    
    # Generate POOLER_TENANT_ID
    local tenant=$(get_env_value "POOLER_TENANT_ID")
    if is_placeholder "$tenant"; then
        local new_tenant="tenant-$(openssl rand -hex 4)"
        sed -i "s|^POOLER_TENANT_ID=.*|POOLER_TENANT_ID=$new_tenant|" "$ENV_FILE"
        log_info "Generated POOLER_TENANT_ID"
        updated=true
    fi
    
    # Regenerate JWT tokens if needed
    if $jwt_updated; then
        local new_jwt=$(get_env_value "JWT_SECRET")
        local new_anon=$(generate_jwt_token "anon" "$new_jwt")
        local new_service=$(generate_jwt_token "service_role" "$new_jwt")
        
        sed -i "s|^ANON_KEY=.*|ANON_KEY=$new_anon|" "$ENV_FILE"
        sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$new_service|" "$ENV_FILE"
        log_info "Generated ANON_KEY and SERVICE_ROLE_KEY"
    fi
    
    # Mark as initialized
    touch "$INIT_MARKER"
    
    if $updated; then
        log_info "Initialization complete!"
    else
        log_info "All secrets already configured."
    fi
    
    # Always print env info for easy copy from deploy terminal
    print_env_info
    print_mcp_guide
}

# Print env info for deploy terminal (copyable format)
print_env_info() {
    local INSTANCE_NAME=$(get_env_value "INSTANCE_NAME")
    local STUDIO_ORG=$(get_env_value "STUDIO_DEFAULT_ORGANIZATION")
    local STUDIO_PROJECT=$(get_env_value "STUDIO_DEFAULT_PROJECT")
    local DASHBOARD_USER=$(get_env_value "DASHBOARD_USERNAME")
    local DASHBOARD_PASS=$(get_env_value "DASHBOARD_PASSWORD")
    local SUPABASE_URL=$(get_env_value "SUPABASE_PUBLIC_URL")
    local SITE_URL=$(get_env_value "SITE_URL")
    local API_URL=$(get_env_value "API_EXTERNAL_URL")
    local KONG_HTTP=$(get_env_value "KONG_HTTP_PORT")
    local KONG_HTTPS=$(get_env_value "KONG_HTTPS_PORT")
    local ANON_KEY=$(get_env_value "ANON_KEY")
    local SERVICE_KEY=$(get_env_value "SERVICE_ROLE_KEY")

    echo ""
    echo "================================================================================"
    echo "                    SUPABASE ENVIRONMENT INFO"
    echo "================================================================================"
    echo ""
    echo "Instance: ${INSTANCE_NAME:-supabase}"
    echo "Generated at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "DASHBOARD LOGIN"
    echo "--------------------------------------------------------------------------------"
    echo ""
    echo "  URL:      ${SUPABASE_URL:-http://localhost:8000}"
    echo "  Username: ${DASHBOARD_USER:-supabase}"
    echo "  Password: ${DASHBOARD_PASS}"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "PROJECT INFO"
    echo "--------------------------------------------------------------------------------"
    echo ""
    echo "  Organization: ${STUDIO_ORG:-Default Organization}"
    echo "  Project:      ${STUDIO_PROJECT:-Default Project}"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "URLS"
    echo "--------------------------------------------------------------------------------"
    echo ""
    echo "  SUPABASE_PUBLIC_URL: ${SUPABASE_URL:-http://localhost:8000}"
    echo "  SITE_URL:            ${SITE_URL:-http://localhost:3000}"
    echo "  API_EXTERNAL_URL:    ${API_URL:-http://localhost:8000}"
    echo "  KONG_HTTP_PORT:      ${KONG_HTTP:-8000}"
    echo "  KONG_HTTPS_PORT:     ${KONG_HTTPS:-8443}"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "API KEYS (copy these for your app)"
    echo "--------------------------------------------------------------------------------"
    echo ""
    echo "ANON_KEY:"
    echo "${ANON_KEY}"
    echo ""
    echo "SERVICE_ROLE_KEY:"
    echo "${SERVICE_KEY}"
    echo ""
    echo "================================================================================"
    echo ""
}

# Print MCP connection guide for deploy terminal
print_mcp_guide() {
    local SUPABASE_URL=$(get_env_value "SUPABASE_PUBLIC_URL")
    local SERVICE_ROLE_KEY=$(get_env_value "SERVICE_ROLE_KEY")
    local ANON_KEY=$(get_env_value "ANON_KEY")
    
    SUPABASE_URL="${SUPABASE_URL:-http://localhost:8000}"

    echo ""
    echo "================================================================================"
    echo "                    SUPABASE MCP CONNECTION GUIDE"
    echo "================================================================================"
    echo ""
    echo "{"
    echo "  \"mcpServers\": {"
    echo "    \"supabase\": {"
    echo "      \"command\": \"npx\","
    echo "      \"args\": ["
    echo "        \"-y\","
    echo "        \"@supabase/mcp-server-supabase@latest\","
    echo "        \"--supabase-url\", \"${SUPABASE_URL}\","
    echo "        \"--supabase-key\", \"${SERVICE_ROLE_KEY}\""
    echo "      ]"
    echo "    }"
    echo "  }"
    echo "}"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo ""
    echo "SUPABASE_URL=${SUPABASE_URL}"
    echo "SUPABASE_ANON_KEY=${ANON_KEY}"
    echo "SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}"
    echo ""
    echo "WARNING: Keep SERVICE_ROLE_KEY secret! It bypasses Row Level Security."
    echo ""
    echo "================================================================================"
    echo ""
}

main "$@"
