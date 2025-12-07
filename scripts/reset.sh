#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Reset Supabase Instance
# ═══════════════════════════════════════════════════════════════════════════════
#
# Completely removes all data and containers.
# Use this to start fresh.
#
# Usage: ./scripts/reset.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

main() {
    echo ""
    log_error "═══════════════════════════════════════════════════════════════"
    log_error "⚠️  COMPLETE RESET - ALL DATA WILL BE DELETED"
    log_error "═══════════════════════════════════════════════════════════════"
    echo ""
    
    read -p "Are you sure? Type 'RESET' to confirm: " -r
    echo
    if [[ "$REPLY" != "RESET" ]]; then
        log_info "Aborted."
        exit 0
    fi
    
    cd "$PROJECT_ROOT"
    
    log_info "Stopping all containers..."
    docker compose down -v --remove-orphans 2>/dev/null || true
    
    log_info "Removing data volumes..."
    rm -rf "$PROJECT_ROOT/volumes/db/data"
    rm -rf "$PROJECT_ROOT/volumes/storage"
    
    log_info "Recreating empty directories..."
    mkdir -p "$PROJECT_ROOT/volumes/db/data"
    mkdir -p "$PROJECT_ROOT/volumes/storage"
    
    echo ""
    log_info "✅ Reset complete!"
    log_info "Run './scripts/init-instance.sh' to reinitialize."
}

main "$@"
