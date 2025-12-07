#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Supabase Environment Info
# ═══════════════════════════════════════════════════════════════════════════════
#
# Displays current environment configuration in container logs.
# View this via: docker logs <instance>-env-info
#
# ═══════════════════════════════════════════════════════════════════════════════

ENV_FILE="/app/.env"

# Get env value
get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

# Mask secret (show first 4 and last 4 chars)
mask_secret() {
    local value="$1"
    local len=${#value}
    if [[ $len -gt 12 ]]; then
        echo "${value:0:4}...${value: -4}"
    else
        echo "****"
    fi
}

# Wait for .env to be ready
wait_for_env() {
    local retries=30
    while [[ ! -f "$ENV_FILE" ]] && [[ $retries -gt 0 ]]; do
        echo "[ENV] Waiting for initialization..."
        sleep 2
        retries=$((retries - 1))
    done
    
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "[ENV] ERROR: .env file not found after timeout"
        exit 1
    fi
}

print_env_info() {
    # Load values
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
    
    local PG_PASS=$(get_env_value "POSTGRES_PASSWORD")
    local JWT_SECRET=$(get_env_value "JWT_SECRET")
    local ANON_KEY=$(get_env_value "ANON_KEY")
    local SERVICE_KEY=$(get_env_value "SERVICE_ROLE_KEY")
    local VAULT_KEY=$(get_env_value "VAULT_ENC_KEY")

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
    echo "  ANON_KEY:"
    echo "  ${ANON_KEY}"
    echo ""
    echo "  SERVICE_ROLE_KEY (keep secret!):"
    echo "  ${SERVICE_KEY}"
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "SECRETS (masked for security)"
    echo "--------------------------------------------------------------------------------"
    echo ""
    echo "  POSTGRES_PASSWORD: $(mask_secret "$PG_PASS")"
    echo "  JWT_SECRET:        $(mask_secret "$JWT_SECRET")"
    echo "  VAULT_ENC_KEY:     $(mask_secret "$VAULT_KEY")"
    echo ""
    echo "  To see full secrets, check your .env file or platform environment variables."
    echo ""
    echo "================================================================================"
    echo "           Info refreshes every 5 minutes | View: docker logs <instance>-env-info"
    echo "================================================================================"
    echo ""
}

main() {
    wait_for_env
    
    while true; do
        print_env_info
        sleep 300  # Refresh every 5 minutes
    done
}

main
