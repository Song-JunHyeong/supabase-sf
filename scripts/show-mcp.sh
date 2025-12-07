#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Show MCP Connection Guide (for supabase-mcp-sf)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage: ./scripts/show-mcp.sh
#
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env file not found. Run 'docker compose up -d' first."
    exit 1
fi

SUPABASE_URL=$(get_env_value "SUPABASE_PUBLIC_URL")
SERVICE_ROLE_KEY=$(get_env_value "SERVICE_ROLE_KEY")
ANON_KEY=$(get_env_value "ANON_KEY")
SUPABASE_URL="${SUPABASE_URL:-<URL>}"

printf "\n"
printf "================================================================================\n"
printf "              SUPABASE MCP CONNECTION GUIDE (Self-Hosted)\n"
printf "================================================================================\n"
printf "\n"
printf "Package: @jun-b/supabase-mcp-sf@latest\n"
printf "\n"
printf "--------------------------------------------------------------------------------\n"
printf "MCP CONFIGURATION TEMPLATE\n"
printf "--------------------------------------------------------------------------------\n"
printf "\n"
printf "Copy this to your MCP config file and replace <...> with values below:\n"
printf "\n"
cat << 'EOF'
{
  "mcpServers": {
    "supabase-sf": {
      "command": "npx",
      "args": ["-y", "@jun-b/supabase-mcp-sf@latest"],
      "env": {
        "SUPABASE_URL": "<SUPABASE_URL>",
        "SUPABASE_SERVICE_ROLE_KEY": "<SERVICE_ROLE_KEY>",
        "SUPABASE_ANON_KEY": "<ANON_KEY>"
      }
    }
  }
}
EOF
printf "\n"
printf "Config file locations:\n"
printf "  Claude:       ~/Library/Application Support/Claude/claude_desktop_config.json\n"
printf "  Cursor:       .cursor/mcp.json\n"  
printf "  Antigravity:  ~/.gemini/antigravity/mcp_config.json\n"
printf "\n"
printf "--------------------------------------------------------------------------------\n"
printf "YOUR VALUES (copy these)\n"
printf "--------------------------------------------------------------------------------\n"
printf "\n"
printf "SUPABASE_URL:\n"
printf "%s\n" "$SUPABASE_URL"
printf "\n"
printf "SERVICE_ROLE_KEY:\n"
printf "%s\n" "$SERVICE_ROLE_KEY"
printf "\n"
printf "ANON_KEY:\n"
printf "%s\n" "$ANON_KEY"
printf "\n"
printf "================================================================================\n"
printf "WARNING: SERVICE_ROLE_KEY has full database access. Keep it secret!\n"
printf "================================================================================\n"
printf "\n"
