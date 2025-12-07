#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Show Environment Info
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage: ./scripts/show-env.sh
#
# Displays current environment configuration including:
# - Dashboard login credentials
# - Public URLs
# - API keys (ANON_KEY, SERVICE_ROLE_KEY)
#
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Get env value
get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

# Check .env exists
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env file not found. Run 'docker compose up -d' first."
    exit 1
fi

# Load values
INSTANCE_NAME=$(get_env_value "INSTANCE_NAME")
STUDIO_ORG=$(get_env_value "STUDIO_DEFAULT_ORGANIZATION")
STUDIO_PROJECT=$(get_env_value "STUDIO_DEFAULT_PROJECT")
DASHBOARD_USER=$(get_env_value "DASHBOARD_USERNAME")
DASHBOARD_PASS=$(get_env_value "DASHBOARD_PASSWORD")
SUPABASE_URL=$(get_env_value "SUPABASE_PUBLIC_URL")
SITE_URL=$(get_env_value "SITE_URL")
API_URL=$(get_env_value "API_EXTERNAL_URL")
KONG_HTTP=$(get_env_value "KONG_HTTP_PORT")
KONG_HTTPS=$(get_env_value "KONG_HTTPS_PORT")
ANON_KEY=$(get_env_value "ANON_KEY")
SERVICE_KEY=$(get_env_value "SERVICE_ROLE_KEY")

printf "\n"
printf "================================================================================\n"
printf "                    SUPABASE ENVIRONMENT INFO\n"
printf "================================================================================\n"
printf "\n"
printf "Instance: %s\n" "${INSTANCE_NAME:-supabase}"
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
printf "ANON_KEY:\n%s\n\n" "${ANON_KEY}"
printf "SERVICE_ROLE_KEY:\n%s\n\n" "${SERVICE_KEY}"
printf "================================================================================\n"
printf "\n"
