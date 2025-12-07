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

    local GENERATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
    local MASKED_PG_PASS=$(mask_secret "$PG_PASS")
    local MASKED_JWT_SECRET=$(mask_secret "$JWT_SECRET")
    local MASKED_VAULT_KEY=$(mask_secret "$VAULT_KEY")

    printf "\n"
    printf "================================================================================\n"
    printf "                    SUPABASE ENVIRONMENT INFO\n"
    printf "================================================================================\n"
    printf "\n"
    printf "Instance: %s\n" "${INSTANCE_NAME:-supabase}"
    printf "Generated at: %s\n" "$GENERATED_AT"
    printf "\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "DASHBOARD LOGIN\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "\n"
    printf "  URL:      %s\n" "${SUPABASE_URL:-http://localhost}"
    printf "  Username: %s\n" "${DASHBOARD_USER:-supabase}"
    printf "  Password: %s\n" "${DASHBOARD_PASS}"
    printf "\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "PROJECT INFO\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "\n"
    printf "  Organization: %s\n" "${STUDIO_ORG:-Default Organization}"
    printf "  Project:      %s\n" "${STUDIO_PROJECT:-Default Project}"
    printf "\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "URLS\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "\n"
    printf "  SUPABASE_PUBLIC_URL:\n    %s\n" "${SUPABASE_URL:-http://localhost}"
    printf "  SITE_URL:\n    %s\n" "${SITE_URL:-http://localhost:3000}"
    printf "  API_EXTERNAL_URL:\n    %s\n" "${API_URL:-http://localhost}"
    printf "  KONG_HTTP_PORT:  %s\n" "${KONG_HTTP:-8000}"
    printf "  KONG_HTTPS_PORT: %s\n" "${KONG_HTTPS:-8443}"
    printf "\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "API KEYS (copy these for your app)\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "\n"
    printf "ANON_KEY:\n%s\n\n" "$ANON_KEY"
    printf "SERVICE_ROLE_KEY (keep secret!):\n%s\n\n" "$SERVICE_KEY"
    printf "--------------------------------------------------------------------------------\n"
    printf "SECRETS (masked for security)\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "\n"
    printf "  POSTGRES_PASSWORD: %s\n" "$MASKED_PG_PASS"
    printf "  JWT_SECRET:        %s\n" "$MASKED_JWT_SECRET"
    printf "  VAULT_ENC_KEY:     %s\n" "$MASKED_VAULT_KEY"
    printf "\n"
    printf "  To see full secrets, check your .env file or platform environment variables.\n"
    printf "\n"
    printf "================================================================================\n"
    printf "           Info refreshes every 5 minutes\n"
    printf "================================================================================\n"
    printf "\n"
}

main() {
    wait_for_env
    
    # Initial print
    print_env_info
    
    # Watch for .env changes using inotify (falls back to polling if unavailable)
    if command -v inotifywait &> /dev/null; then
        echo "[ENV] Watching for .env changes (inotify)..."
        while true; do
            inotifywait -qq -e modify -e close_write "$ENV_FILE" 2>/dev/null
            sleep 1  # Brief delay to avoid rapid updates
            print_env_info
        done
    else
        echo "[ENV] inotifywait not available, falling back to 5-minute polling..."
        while true; do
            sleep 300
            print_env_info
        done
    fi
}

main
