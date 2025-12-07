#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Supabase Database Backup
# ═══════════════════════════════════════════════════════════════════════════════
#
# Creates a PostgreSQL dump of all databases.
#
# Usage: 
#   ./scripts/backup.sh              # Backup to backups/ folder
#   ./scripts/backup.sh /path/to    # Backup to custom location
#
# Restore:
#   docker exec -i supabase-db psql -U postgres < backup_file.sql
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Backup directory
    local BACKUP_DIR="${1:-$PROJECT_ROOT/backups}"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.sql"
    
    log_info "Supabase Database Backup"
    echo ""
    
    # Check if DB is running
    if ! docker inspect supabase-db >/dev/null 2>&1; then
        log_error "supabase-db container is not running"
        exit 1
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Perform backup
    log_info "Creating backup..."
    log_info "Target: $BACKUP_FILE"
    
    if docker exec supabase-db pg_dumpall -U postgres > "$BACKUP_FILE" 2>/dev/null; then
        # Get file size
        local SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        
        echo ""
        log_info "✅ Backup completed successfully!"
        log_info "File: $BACKUP_FILE"
        log_info "Size: $SIZE"
        echo ""
        log_info "To restore: docker exec -i supabase-db psql -U postgres < $BACKUP_FILE"
    else
        log_error "Backup failed!"
        rm -f "$BACKUP_FILE"
        exit 1
    fi
    
    # Optional: cleanup old backups (keep last 10)
    local BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/backup_*.sql 2>/dev/null | wc -l)
    if [[ $BACKUP_COUNT -gt 10 ]]; then
        log_info "Cleaning up old backups (keeping last 10)..."
        ls -1t "$BACKUP_DIR"/backup_*.sql | tail -n +11 | xargs rm -f
    fi
}

main "$@"
