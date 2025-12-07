#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Common functions for Supabase Self-Host scripts
# ═══════════════════════════════════════════════════════════════════════════════
#
# Source this file in other scripts:
#   source "$(dirname "$0")/common.sh"
#
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get instance name from .env or default to 'supabase'
get_instance_name() {
    if [[ -f "$ENV_FILE" ]]; then
        local name=$(grep "^INSTANCE_NAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1)
        echo "${name:-supabase}"
    else
        echo "supabase"
    fi
}

# Get container name with instance prefix
get_container_name() {
    local service="$1"
    local instance=$(get_instance_name)
    echo "${instance}-${service}"
}

# Get env value
get_env_value() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | head -1 || echo ""
}

# Common log functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Container names (dynamic)
CONTAINER_DB=""
CONTAINER_AUTH=""
CONTAINER_REST=""
CONTAINER_STORAGE=""
CONTAINER_META=""
CONTAINER_FUNCTIONS=""
CONTAINER_REALTIME=""
CONTAINER_POOLER=""
CONTAINER_KONG=""
CONTAINER_STUDIO=""
CONTAINER_INIT=""
CONTAINER_MCP=""

# Initialize container names
init_container_names() {
    local instance=$(get_instance_name)
    CONTAINER_DB="${instance}-db"
    CONTAINER_AUTH="${instance}-auth"
    CONTAINER_REST="${instance}-rest"
    CONTAINER_STORAGE="${instance}-storage"
    CONTAINER_META="${instance}-meta"
    CONTAINER_FUNCTIONS="${instance}-functions"
    CONTAINER_REALTIME="realtime-dev.${instance}-realtime"
    CONTAINER_POOLER="${instance}-pooler"
    CONTAINER_KONG="${instance}-kong"
    CONTAINER_STUDIO="${instance}-studio"
    CONTAINER_INIT="${instance}-init"
    CONTAINER_MCP="${instance}-mcp-guide"
}

# Auto-init container names when sourced
init_container_names
