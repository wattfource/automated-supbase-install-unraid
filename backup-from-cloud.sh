#!/usr/bin/env bash
# ============================================================================
# SUPABASE CLOUD BACKUP UTILITY
# 
# Downloads database backup directly from Supabase Cloud to self-hosted instance.
# Supports both direct connection (port 5432) and pooled connection (port 6543).
# 
# Usage:
#   sudo bash backup-from-cloud.sh
#   sudo bash backup-from-cloud.sh --auto-restore
# 
# The script will prompt for Supabase Cloud credentials and download the database.
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
BACKUP_DIR="/srv/supabase/backups"
LOGFILE="${SCRIPT_DIR}/backup-from-cloud-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR" "$BACKUP_DIR"

log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE" >/dev/null
}

print_header() {
    printf "${C_CYAN}╔════════════════════════════════════════════════════════════════╗${C_RESET}\n"
    printf "${C_CYAN}║         SUPABASE CLOUD BACKUP UTILITY                          ║${C_RESET}\n"
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

ask() { 
    local p="$1" d="${2-}" v
    printf "${C_WHITE}%s${C_RESET}" "$p" >&2
    [[ -n "$d" ]] && printf " ${C_CYAN}[%s]${C_RESET}" "$d" >&2
    printf ": " >&2
    read -r v </dev/tty
    echo "${v:-$d}"
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

# Install PostgreSQL client tools if needed
install_pg_client() {
    if command -v pg_dump &> /dev/null && command -v psql &> /dev/null; then
        print_success "PostgreSQL client tools already installed"
        return 0
    fi
    
    print_warning "PostgreSQL client tools not found"
    
    if [[ $(ask_yn "Install PostgreSQL client tools?" "y") = "n" ]]; then
        print_error "PostgreSQL client tools are required"
        exit 1
    fi
    
    print_info "Installing PostgreSQL client tools..."
    log "Installing postgresql-client"
    
    export DEBIAN_FRONTEND=noninteractive
    
    if apt-get update -qq >> "$LOGFILE" 2>&1 && \
       apt-get install -y -qq postgresql-client >> "$LOGFILE" 2>&1; then
        print_success "PostgreSQL client tools installed"
        log "PostgreSQL client installed successfully"
    else
        print_error "Failed to install PostgreSQL client tools"
        print_info "Check log: $LOGFILE"
        exit 1
    fi
}

# Save credentials to file
save_credentials() {
    local host="$1"
    local port="$2"
    local db="$3"
    local user="$4"
    local pass="$5"
    
    local cred_file="/root/.supabase-cloud-credentials"
    
    # Use printf with %q to properly escape special characters
    cat > "$cred_file" << 'EOF'
# Supabase Cloud Credentials
# Created: $(date)
EOF
    
    printf 'SUPABASE_CLOUD_HOST=%q\n' "$host" >> "$cred_file"
    printf 'SUPABASE_CLOUD_PORT=%q\n' "$port" >> "$cred_file"
    printf 'SUPABASE_CLOUD_DB=%q\n' "$db" >> "$cred_file"
    printf 'SUPABASE_CLOUD_USER=%q\n' "$user" >> "$cred_file"
    printf 'SUPABASE_CLOUD_PASS=%q\n' "$pass" >> "$cred_file"
    
    chmod 600 "$cred_file"
    log "Credentials saved to $cred_file"
    print_success "Credentials saved for future use"
}

# Load saved credentials
load_credentials() {
    local cred_file="/root/.supabase-cloud-credentials"
    
    if [ -f "$cred_file" ]; then
        source "$cred_file"
        return 0
    else
        return 1
    fi
}

# Test database connection
test_connection() {
    local host="$1"
    local port="$2"
    local db="$3"
    local user="$4"
    local pass="$5"
    
    print_info "Testing connection to Supabase Cloud..."
    log "Testing connection: host=$host port=$port db=$db user=$user"
    
    # Test with psql
    if PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d "$db" \
        -c "SELECT version();" >> "$LOGFILE" 2>&1; then
        print_success "Connection successful"
        log "Connection test passed"
        return 0
    else
        print_error "Connection failed"
        log "Connection test failed"
        print_info "Check firewall rules and credentials"
        print_info "Ensure your IP is allowed in Supabase Cloud dashboard"
        return 1
    fi
}

# Backup database from cloud
backup_from_cloud() {
    local host="$1"
    local port="$2"
    local db="$3"
    local user="$4"
    local pass="$5"
    local output_file="$6"
    
    print_info "Starting backup from Supabase Cloud..."
    print_warning "This may take several minutes depending on database size..."
    log "Starting pg_dump: host=$host port=$port db=$db output=$output_file"
    
    # Use plain SQL format - comprehensive backup of everything
    # Includes: schemas, tables, functions, triggers, policies, extensions, data
    if PGPASSWORD="$pass" pg_dump -h "$host" -p "$port" -U "$user" -d "$db" \
        --format=plain \
        --no-owner \
        --no-acl \
        --create \
        --clean \
        --if-exists \
        --file="$output_file" \
        2>&1 | tee -a "$LOGFILE"; then
        
        # Compress the SQL file
        print_info "Compressing backup..."
        gzip "$output_file"
        output_file="${output_file}.gz"
        
        local size=$(du -h "$output_file" | cut -f1)
        print_success "Backup completed: $output_file ($size)"
        log "Backup successful: $output_file (size: $size)"
        return 0
    else
        print_error "Backup failed"
        log "pg_dump failed"
        return 1
    fi
}

# Get database info
get_db_info() {
    local host="$1"
    local port="$2"
    local db="$3"
    local user="$4"
    local pass="$5"
    
    print_info "Fetching database information..."
    
    echo
    printf "${C_WHITE}Database Statistics:${C_RESET}\n"
    
    # Get version
    PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d "$db" \
        -c "SELECT version();" 2>/dev/null | grep PostgreSQL || echo "Unable to get version"
    
    echo
    
    # Get database size
    PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d "$db" \
        -c "SELECT pg_size_pretty(pg_database_size('$db')) as size;" 2>/dev/null | tail -3 || echo "Unable to get size"
    
    echo
    
    # Get table count by schema
    printf "${C_WHITE}Tables by Schema:${C_RESET}\n"
    PGPASSWORD="$pass" psql -h "$host" -p "$port" -U "$user" -d "$db" \
        -c "SELECT schemaname, COUNT(*) as tables FROM pg_tables GROUP BY schemaname ORDER BY tables DESC LIMIT 5;" 2>/dev/null | tail -8 || echo "Unable to get table info"
    
    echo
}

#==============================================================================
# MAIN BACKUP FLOW
#==============================================================================

log "=== Supabase Cloud Backup Started ==="
log "Script: $0"
log "User: $(whoami)"

require_root
clear
print_header

# Check for auto-restore flag
AUTO_RESTORE=false
if [[ "${1:-}" = "--auto-restore" ]]; then
    AUTO_RESTORE=true
    print_info "Auto-restore mode enabled"
fi

# Install PostgreSQL client if needed
install_pg_client

echo
print_info "This script will backup your Supabase Cloud database"
print_info "You'll need your Supabase Cloud connection details"
echo

printf "${C_RED}⚠️  IMPORTANT PREREQUISITE:${C_RESET}\n"
echo "   ${C_YELLOW}IPv4 Direct Connection Add-on is REQUIRED${C_RESET}"
echo "   This is a paid add-on in Supabase Cloud"
echo
printf "${C_WHITE}To enable IPv4 add-on:${C_RESET}\n"
echo "   1. Go to your Supabase Cloud project"
echo "   2. Settings → Add-ons → IPv4 Address"
echo "   3. Enable the IPv4 add-on"
echo "   4. Wait for provisioning (few minutes)"
echo
printf "${C_YELLOW}Where to find your credentials (after enabling IPv4):${C_RESET}\n"
echo "1. Go to Settings → Database → Connection string"
echo "2. Select 'Direct connection' (port 5432, NOT pooled)"
echo "3. Ensure 'IPv4 compatible' is shown"
echo "4. Copy these values:"
echo "   • Host: Just the hostname (e.g. db.xxxxx.supabase.co)"
echo "   • NO https:// prefix"
echo "   • Port: 5432"
echo "   • Database: postgres"
echo "   • User: postgres"
echo "   • Password: (can contain special characters)"
echo

# Try to load saved credentials
USE_SAVED=false
if load_credentials && [ -n "${SUPABASE_CLOUD_HOST:-}" ]; then
    print_info "Found saved credentials"
    printf "  Host: ${C_CYAN}%s${C_RESET}\n" "$SUPABASE_CLOUD_HOST"
    printf "  Port: ${C_CYAN}%s${C_RESET}\n" "$SUPABASE_CLOUD_PORT"
    printf "  DB:   ${C_CYAN}%s${C_RESET}\n" "$SUPABASE_CLOUD_DB"
    printf "  User: ${C_CYAN}%s${C_RESET}\n" "$SUPABASE_CLOUD_USER"
    echo
    
    if [[ $(ask_yn "Use saved credentials?" "y") = "y" ]]; then
        USE_SAVED=true
        DB_HOST="$SUPABASE_CLOUD_HOST"
        DB_PORT="$SUPABASE_CLOUD_PORT"
        DB_NAME="$SUPABASE_CLOUD_DB"
        DB_USER="$SUPABASE_CLOUD_USER"
        DB_PASS="$SUPABASE_CLOUD_PASS"
    fi
fi

# Prompt for credentials if not using saved
if [ "$USE_SAVED" = false ]; then
    printf "${C_WHITE}Enter Supabase Cloud credentials:${C_RESET}\n\n"
    
    DB_HOST=$(ask "Host - hostname ONLY, no https:// (e.g. db.xxxxx.supabase.co)" "")
    while [ -z "$DB_HOST" ]; do
        print_error "Host cannot be empty"
        DB_HOST=$(ask "Host (hostname only)" "")
    done
    
    # Strip https:// if user included it
    DB_HOST="${DB_HOST#https://}"
    DB_HOST="${DB_HOST#http://}"
    
    DB_PORT=$(ask "Port" "5432")
    DB_NAME=$(ask "Database" "postgres")
    DB_USER=$(ask "User" "postgres")
    
    # Hide password input - read into variable safely
    printf "${C_WHITE}Password (can contain special characters): ${C_RESET}" >&2
    IFS= read -rs DB_PASS </dev/tty
    echo
    
    while [ -z "$DB_PASS" ]; do
        print_error "Password cannot be empty"
        printf "${C_WHITE}Password: ${C_RESET}" >&2
        IFS= read -rs DB_PASS </dev/tty
        echo
    done
    
    echo
    
    # Offer to save credentials
    if [[ $(ask_yn "Save credentials for future use?" "y") = "y" ]]; then
        save_credentials "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$DB_PASS"
    fi
fi

# Test connection
echo
if ! test_connection "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$DB_PASS"; then
    print_error "Cannot proceed with failed connection"
    echo
    print_info "Common issues:"
    echo "  • Incorrect credentials"
    echo "  • Your IP not whitelisted in Supabase Cloud dashboard"
    echo "  • Firewall blocking port $DB_PORT"
    echo "  • SSL/TLS connection issues"
    exit 1
fi

# Show database info
echo
get_db_info "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$DB_PASS"

# Confirm backup
echo
print_warning "Ready to backup database from Supabase Cloud"
echo

if [[ $(ask_yn "Proceed with backup?" "y") = "n" ]]; then
    print_warning "Backup cancelled by user"
    log "Backup cancelled by user"
    exit 0
fi

# Create output file
BACKUP_FILE="${BACKUP_DIR}/cloud-backup-$(date +%Y%m%d-%H%M%S).sql"
log "Output file: $BACKUP_FILE"

# Perform backup
echo
if ! backup_from_cloud "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$DB_PASS" "$BACKUP_FILE"; then
    print_error "Backup failed"
    exit 1
fi

# Success summary
echo
printf "${C_GREEN}╔════════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "${C_GREEN}║                    BACKUP COMPLETED                            ║${C_RESET}\n"
printf "${C_GREEN}╚════════════════════════════════════════════════════════════════╝${C_RESET}\n"
echo

# Update backup file path (it's now compressed)
BACKUP_FILE="${BACKUP_FILE}.gz"
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
print_success "Cloud database backed up successfully"
print_success "Backup saved to: $BACKUP_FILE"
print_success "Backup size: $BACKUP_SIZE"
print_success "Format: Compressed SQL (.sql.gz)"
echo

# Offer to restore to local instance
SHOULD_RESTORE=false
if [ "$AUTO_RESTORE" = true ]; then
    SHOULD_RESTORE=true
    print_info "Auto-restore mode: will restore to local instance"
elif [[ $(ask_yn "Restore to local self-hosted instance now?" "y") = "y" ]]; then
    SHOULD_RESTORE=true
fi

if [ "$SHOULD_RESTORE" = true ]; then
    echo
    print_info "Starting restore to local instance..."
    
    RESTORE_SCRIPT="/srv/supabase/scripts/restore-database.sh"
    
    if [ ! -f "$RESTORE_SCRIPT" ]; then
        print_warning "Restore script not found, downloading..."
        curl -fsSL "https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/restore-database.sh" \
            -o "$RESTORE_SCRIPT" && chmod +x "$RESTORE_SCRIPT"
    fi
    
    if [ -f "$RESTORE_SCRIPT" ]; then
        echo
        bash "$RESTORE_SCRIPT" "$BACKUP_FILE"
    else
        print_error "Could not download restore script"
        print_info "You can manually restore later:"
        printf "  ${C_CYAN}sudo bash /srv/supabase/scripts/restore-database.sh $BACKUP_FILE${C_RESET}\n"
    fi
else
    echo
    print_info "To restore this backup later, run:"
    printf "  ${C_CYAN}sudo bash /srv/supabase/scripts/restore-database.sh $BACKUP_FILE${C_RESET}\n"
fi

echo
printf "${C_CYAN}Backup log: $LOGFILE${C_RESET}\n\n"
log "=== Backup completed successfully ==="

