#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Supabase MCP Connection Guide (for supabase-mcp-sf)
# ═══════════════════════════════════════════════════════════════════════════════
#
# View via: docker logs supabase-mcp-guide
#
# ═══════════════════════════════════════════════════════════════════════════════

ENV_FILE="/app/.env"

get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

wait_for_env() {
    local retries=30
    while [[ ! -f "$ENV_FILE" ]] && [[ $retries -gt 0 ]]; do
        echo "[MCP] Waiting for initialization..."
        sleep 2
        retries=$((retries - 1))
    done
    
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "[MCP] ERROR: .env file not found after timeout"
        exit 1
    fi
}

print_connection_info() {
    local SUPABASE_URL=$(get_env_value "SUPABASE_PUBLIC_URL")
    local SERVICE_ROLE_KEY=$(get_env_value "SERVICE_ROLE_KEY")
    local ANON_KEY=$(get_env_value "ANON_KEY")
    SUPABASE_URL="${SUPABASE_URL:-http://localhost}"

    printf "\n"
    printf "================================================================================\n"
    printf "              SUPABASE MCP CONNECTION GUIDE (Self-Hosted)\n"
    printf "================================================================================\n"
    printf "\n"
    printf "Package: @jun-b/supabase-mcp-sf\n"
    printf "GitHub:  https://github.com/Song-JunHyeong/supabase-mcp-sf\n"
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
      "args": ["-y", "@jun-b/supabase-mcp-sf"],
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
    printf "--------------------------------------------------------------------------------\n"
    printf "SDK CONFIGURATION\n"
    printf "--------------------------------------------------------------------------------\n"
    printf "\n"
    printf "JavaScript:  createClient('<SUPABASE_URL>', '<ANON_KEY>')\n"
    printf "Python:      create_client('<SUPABASE_URL>', '<ANON_KEY>')\n"
    printf "\n"
    printf "================================================================================\n"
    printf "WARNING: SERVICE_ROLE_KEY has full database access. Keep it secret!\n"
    printf "================================================================================\n"
    printf "           Connection info refreshes every 5 minutes\n"
    printf "================================================================================\n"
    printf "\n"
}

main() {
    wait_for_env
    print_connection_info
    
    if command -v inotifywait &> /dev/null; then
        echo "[MCP] Watching for .env changes..."
        while true; do
            inotifywait -qq -e modify -e close_write "$ENV_FILE" 2>/dev/null
            sleep 1
            print_connection_info
        done
    else
        while true; do
            sleep 300
            print_connection_info
        done
    fi
}

main
