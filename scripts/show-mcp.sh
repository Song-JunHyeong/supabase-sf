#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Show MCP Connection Guide
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage: ./scripts/show-mcp.sh
#
# Displays MCP connection configuration for:
# - Claude Desktop / Cursor
# - Environment variables for SDK
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
SUPABASE_URL=$(get_env_value "SUPABASE_PUBLIC_URL")
SERVICE_ROLE_KEY=$(get_env_value "SERVICE_ROLE_KEY")
ANON_KEY=$(get_env_value "ANON_KEY")

SUPABASE_URL="${SUPABASE_URL:-http://localhost:8000}"

echo ""
echo "================================================================================"
echo "                    SUPABASE MCP CONNECTION GUIDE"
echo "================================================================================"
echo ""
echo "Add this to your claude_desktop_config.json or .cursor/mcp.json:"
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
echo "ENVIRONMENT VARIABLES"
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
