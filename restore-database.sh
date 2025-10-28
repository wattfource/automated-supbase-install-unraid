#!/usr/bin/env bash
# ============================================================================
# SUPABASE DATABASE RESTORE UTILITY
# 
# Restores PostgreSQL dumps or Supabase backups to a self-hosted instance.
# Supports multiple backup formats:
#   - PostgreSQL custom format (.dump, .backup)
#   - SQL plain text (.sql)
#   - Compressed SQL (.sql.gz)
# 
# Usage:
#   sudo bash restore-database.sh /tmp/backup.dump
#   sudo bash restore-database.sh /path/to/backup.sql
# ============================================================================
set -euo pipefail

# Color definitions
C_CYAN="\033[1;36m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"
C_RESET="\033[0m"

# Logging
SCRIPT_DIR="/srv/supabase/scripts"
LOGFILE="${SCRIPT_DIR}/restore-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR"

log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE" >/dev/null
}

print_header() {
    printf "${C_CYAN}╔════════════════════════════════════════════════════════════════╗${C_RESET}\n"
    printf "${C_CYAN}║         SUPABASE DATABASE RESTORE UTILITY                      ║${C_RESET}\n"
    printf "${C_CYAN}╚════════════════════════════════════════════════════════════════╝${C_RESET}\n\n"
}

print_info() {
    printf "${C_CYAN}◉${C_RESET} %s\n" "$1"
}

print_success() {
    printf "${C_GREEN}✓${C_RESET} %s\n" "$1"
}

print_warning() {
    printf "${C_YELLOW}⚠${C_RESET} %s\n" "$1"
}

print_error() {
    printf "${C_RED}✗${C_RESET} %s\n" "$1" >&2
}

ask_yn() {
    local p="$1" d="${2:-y}" a
    while true; do
        printf "${C_WHITE}%s${C_RESET} [" "$p" >&2
        [[ "$d" = "y" ]] && printf "Y/n" >&2 || printf "y/N" >&2
        printf "]: " >&2
        read -r a </dev/tty || true
        a="${a:-$d}"
        case "$a" in
            y|Y) echo y; return;;
            n|N) echo n; return;;
            *) print_warning "Please enter y or n";;
        esac
    done
}

# Check requirements
require_root() { 
    [[ ${EUID:-$(id -u)} -eq 0 ]] || { 
        print_error "This script must be run as root. Use: sudo bash $0"
        exit 1
    }
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed"
        exit 1
    fi
}

check_supabase_directory() {
    if [ ! -d "/srv/supabase" ]; then
        print_error "Supabase installation not found at /srv/supabase"
        print_info "Please install Supabase first"
        exit 1
    fi
    
    if [ ! -f "/srv/supabase/docker-compose.yml" ]; then
        print_error "docker-compose.yml not found in /srv/supabase"
        exit 1
    fi
}

# Detect backup format
detect_backup_format() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "not_found"
        return
    fi
    
    # Check file extension first
    case "${file,,}" in
        *.sql.gz)
            echo "sql_gz"
            return
            ;;
        *.sql)
            echo "sql"
            return
            ;;
        *.dump|*.backup)
            echo "custom"
            return
            ;;
    esac
    
    # Check magic bytes for gzip
    if file "$file" | grep -q "gzip compressed"; then
        echo "sql_gz"
        return
    fi
    
    # Check for PostgreSQL custom dump format
    if file "$file" | grep -q "PostgreSQL custom"; then
        echo "custom"
        return
    fi
    
    # Check if it's plain text SQL
    if file "$file" | grep -q "ASCII text\|UTF-8"; then
        echo "sql"
        return
    fi
    
    # Default to custom format (pg_restore can detect it)
    echo "custom"
}

# Create pre-restore backup
create_backup() {
    local backup_file="$1"
    
    print_info "Creating safety backup before restore..."
    log "Creating pre-restore backup"
    
    cd /srv/supabase || exit 1
    
    # Check if database is healthy
    if ! docker compose ps db | grep -q "healthy\|Up"; then
        print_warning "Database container is not healthy"
        if [[ $(ask_yn "Continue anyway?" "n") = "n" ]]; then
            exit 1
        fi
    fi
    
    # Create backup
    if docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "$backup_file" 2>>"$LOGFILE"; then
        local size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup created: $backup_file ($size)"
        log "Backup created successfully: $backup_file"
        return 0
    else
        print_error "Failed to create backup"
        log "Backup creation failed"
        return 1
    fi
}

# Restore from custom format (pg_dump -Fc)
restore_custom_format() {
    local backup_file="$1"
    
    print_info "Restoring from PostgreSQL custom format..."
    log "Restoring custom format: $backup_file (mode: $RESTORE_MODE)"
    
    cd /srv/supabase || exit 1
    
    local restore_flags="--clean --if-exists --no-owner --no-acl"
    
    if [ "$RESTORE_MODE" = "schema-only" ]; then
        print_info "Filtering: Schema only (skipping data)"
        restore_flags="$restore_flags --schema-only"
    fi
    
    # Use pg_restore
    if cat "$backup_file" | docker compose exec -T db pg_restore -U postgres -d postgres $restore_flags 2>&1 | tee -a "$LOGFILE"; then
        if [ "$RESTORE_MODE" = "schema-only" ]; then
            print_success "Schema restored successfully (no data)"
        else
            print_success "Database restored successfully (schema + data)"
        fi
        log "Restore completed successfully"
        return 0
    else
        print_warning "Restore completed with some warnings (this is often normal)"
        log "Restore completed with warnings"
        return 0
    fi
}

# Restore from SQL file
restore_sql_format() {
    local backup_file="$1"
    
    print_info "Restoring from SQL format..."
    log "Restoring SQL format: $backup_file (mode: $RESTORE_MODE)"
    
    cd /srv/supabase || exit 1
    
    if [ "$RESTORE_MODE" = "schema-only" ]; then
        print_info "Filtering: Schema only (skipping data)"
        # Filter out COPY/INSERT data, fix COPY markers, and suppress permission errors
        if cat "$backup_file" | \
           sed 's/\\restrict//g; s/\\unrestrict//g' | \
           grep -v "^COPY " | grep -v "^INSERT INTO" | \
           docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=off 2>&1 | tee -a "$LOGFILE"; then
            print_success "Schema restored successfully (no data)"
            log "Schema-only restore completed"
            return 0
        fi
    else
        # Full restore with data
        if cat "$backup_file" | \
           sed 's/\\restrict//g; s/\\unrestrict//g' | \
           docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=off 2>&1 | tee -a "$LOGFILE"; then
            print_success "Database restored successfully (schema + data)"
            log "Full restore completed successfully"
            return 0
        fi
    fi
    
    print_error "Restore failed"
    log "SQL restore failed"
    return 1
}

# Restore from compressed SQL
restore_sql_gz_format() {
    local backup_file="$1"
    
    print_info "Restoring from compressed SQL format..."
    log "Restoring SQL.GZ format: $backup_file (mode: $RESTORE_MODE)"
    
    cd /srv/supabase || exit 1
    
    if [ "$RESTORE_MODE" = "schema-only" ]; then
        print_info "Filtering: Schema only (skipping data)"
        # Filter out COPY/INSERT data, fix COPY markers, suppress permission errors
        if zcat "$backup_file" | \
           sed 's/\\restrict//g; s/\\unrestrict//g' | \
           grep -v "^COPY " | grep -v "^INSERT INTO" | \
           docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=off 2>&1 | tee -a "$LOGFILE"; then
            print_success "Schema restored successfully (no data)"
            log "Schema-only restore completed"
            return 0
        fi
    else
        # Full restore with data
        if zcat "$backup_file" | \
           sed 's/\\restrict//g; s/\\unrestrict//g' | \
           docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=off 2>&1 | tee -a "$LOGFILE"; then
            print_success "Database restored successfully (schema + data)"
            log "Full restore completed successfully"
            return 0
        fi
    fi
    
    print_error "Restore failed"
    log "SQL.GZ restore failed"
    return 1
}

# Verify database health
verify_database() {
    print_info "Verifying database health..."
    
    cd /srv/supabase || exit 1
    
    # Wait for database to be ready
    local max_wait=30
    local count=0
    while [ $count -lt $max_wait ]; do
        if docker compose exec -T db pg_isready -U postgres >/dev/null 2>&1; then
            break
        fi
        sleep 1
        count=$((count + 1))
    done
    
    if [ $count -eq $max_wait ]; then
        print_error "Database is not responding"
        return 1
    fi
    
    # Check database connectivity
    if docker compose exec -T db psql -U postgres -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "Database is healthy and accepting connections"
        
        # Show some stats
        print_info "Database statistics:"
        docker compose exec -T db psql -U postgres -d postgres -c "SELECT schemaname, COUNT(*) as tables FROM pg_tables GROUP BY schemaname ORDER BY tables DESC LIMIT 5;" 2>/dev/null | grep -v "^(" | head -8
        
        return 0
    else
        print_error "Database connectivity check failed"
        return 1
    fi
}

# Restart dependent services
restart_services() {
    print_info "Restarting Supabase services..."
    log "Restarting services"
    
    cd /srv/supabase || exit 1
    
    # Restart services that depend on the database
    local services="auth rest storage meta realtime"
    
    for service in $services; do
        if docker compose ps | grep -q "$service"; then
            print_info "Restarting $service..."
            docker compose restart "$service" >>"$LOGFILE" 2>&1 || true
        fi
    done
    
    # Wait a bit for services to stabilize
    sleep 5
    
    print_success "Services restarted"
}

#==============================================================================
# MAIN RESTORE FLOW
#==============================================================================

log "=== Supabase Database Restore Started ==="
log "Script: $0"
log "User: $(whoami)"

require_root
clear
print_header

# Check arguments
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <backup-file>"
    echo
    print_info "Examples:"
    printf "  ${C_CYAN}$0 /tmp/backup.dump${C_RESET}\n"
    printf "  ${C_CYAN}$0 /tmp/backup.sql${C_RESET}\n"
    printf "  ${C_CYAN}$0 /tmp/backup.sql.gz${C_RESET}\n"
    echo
    exit 1
fi

BACKUP_FILE="$1"

# Validate backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    print_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Show backup file info
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
print_info "Backup file: $BACKUP_FILE"
print_info "File size: $BACKUP_SIZE"
log "Backup file: $BACKUP_FILE (size: $BACKUP_SIZE)"

# Check prerequisites
print_info "Checking prerequisites..."
check_docker
check_supabase_directory
print_success "Prerequisites verified"

# Detect backup format
BACKUP_FORMAT=$(detect_backup_format "$BACKUP_FILE")
print_info "Detected format: $BACKUP_FORMAT"
log "Backup format: $BACKUP_FORMAT"

# Ask what to restore
echo
print_info "What would you like to restore?"
echo
printf "${C_WHITE}1)${C_RESET} Schema only ${C_CYAN}(structure: tables, functions, policies - NO data)${C_RESET}\n"
printf "   ├─ Best for: Fresh start with existing structure\n"
printf "   └─ Result: Empty tables, all functions/policies in place\n"
echo
printf "${C_WHITE}2)${C_RESET} Schema + Data ${C_CYAN}(complete restore)${C_RESET}\n"
printf "   ├─ Best for: Full migration from Supabase Cloud\n"
printf "   └─ Result: Exact copy of source database\n"
echo
printf "${C_WHITE}Choose [1 or 2]: ${C_RESET}" >&2
read -r RESTORE_CHOICE </dev/tty

while [[ ! "$RESTORE_CHOICE" =~ ^[12]$ ]]; do
    print_warning "Please enter 1 or 2"
    printf "${C_WHITE}Choose [1 or 2]: ${C_RESET}" >&2
    read -r RESTORE_CHOICE </dev/tty
done

if [ "$RESTORE_CHOICE" = "1" ]; then
    RESTORE_MODE="schema-only"
    print_info "Selected: Schema only (fresh start)"
else
    RESTORE_MODE="full"
    print_info "Selected: Full restore (schema + data)"
fi

# Confirm restore
echo
print_warning "⚠️  WARNING: This will affect your current database!"
if [ "$RESTORE_MODE" = "schema-only" ]; then
    print_warning "⚠️  Existing tables will be dropped and recreated (empty)"
else
    print_warning "⚠️  All existing data will be replaced"
fi
echo
print_info "A safety backup will be created first."
echo

if [[ $(ask_yn "Do you want to continue with the restore?" "n") = "n" ]]; then
    print_warning "Restore cancelled by user"
    log "Restore cancelled by user"
    exit 0
fi

log "Restore mode: $RESTORE_MODE"

# Create safety backup
SAFETY_BACKUP="/srv/supabase/backups/pre-restore-$(date +%Y%m%d-%H%M%S).dump"
mkdir -p /srv/supabase/backups

if ! create_backup "$SAFETY_BACKUP"; then
    print_error "Failed to create safety backup"
    if [[ $(ask_yn "Continue without safety backup?" "n") = "n" ]]; then
        exit 1
    fi
fi

echo
print_info "Starting restore process..."
print_warning "This may take several minutes depending on database size..."
echo

# Perform restore based on format
case "$BACKUP_FORMAT" in
    custom)
        restore_custom_format "$BACKUP_FILE"
        ;;
    sql)
        restore_sql_format "$BACKUP_FILE"
        ;;
    sql_gz)
        restore_sql_gz_format "$BACKUP_FILE"
        ;;
    *)
        print_error "Unknown backup format: $BACKUP_FORMAT"
        exit 1
        ;;
esac

# Verify database
echo
if ! verify_database; then
    print_error "Database verification failed"
    echo
    print_warning "You may need to restore from the safety backup:"
    printf "  ${C_CYAN}$0 $SAFETY_BACKUP${C_RESET}\n"
    exit 1
fi

# Restart services
echo
restart_services

# Success summary
echo
printf "${C_GREEN}╔════════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "${C_GREEN}║                    RESTORE COMPLETED                           ║${C_RESET}\n"
printf "${C_GREEN}╚════════════════════════════════════════════════════════════════╝${C_RESET}\n"
echo

print_success "Database restored from: $BACKUP_FILE"
print_success "Safety backup saved to: $SAFETY_BACKUP"
echo

print_info "Next steps:"
echo "  1. Test your Supabase instance: http://YOUR-IP:3000"
echo "  2. Verify your data is correct"
echo "  3. Check service status: cd /srv/supabase && docker compose ps"
echo "  4. View logs if needed: cd /srv/supabase && docker compose logs -f"
echo

if [ -f "$SAFETY_BACKUP" ]; then
    print_info "If something went wrong, restore the safety backup:"
    printf "  ${C_CYAN}$0 $SAFETY_BACKUP${C_RESET}\n"
    echo
fi

printf "${C_CYAN}Restore log: $LOGFILE${C_RESET}\n\n"
log "=== Restore completed successfully ==="

