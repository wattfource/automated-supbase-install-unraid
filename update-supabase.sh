#!/usr/bin/env bash
# ============================================================================
# WATTFOURCE SUPABASE UPDATER
# 
# Non-destructive update script for Supabase services and system packages
# Preserves all data, configurations, and environment variables
# ============================================================================
set -euo pipefail

# Get script directory for log file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${SCRIPT_DIR}/supabase-update-$(date +%Y%m%d-%H%M%S).log"

# Color definitions
C_CYAN="\033[1;36m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"
C_RESET="\033[0m"

# Logging functions
log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE" >/dev/null
}

print_header() {
    clear
    printf "${C_CYAN}WATTFOURCE${C_RESET} — Supabase Update Script\n"
    printf "Log: %s\n\n" "$LOGFILE"
}

print_step_header() {
    local step="$1"
    local title="$2"
    printf "\n${C_BLUE}-- %s: %s --${C_RESET}\n\n" "STEP $step" "$title"
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
        printf "${C_WHITE}%s${C_RESET} ${C_CYAN}[" "$p" >&2
        [[ "$d" = "y" ]] && printf "Y/n" >&2 || printf "y/N" >&2
        printf "]${C_RESET}: " >&2
        read -r a </dev/tty || true
        a="${a:-$d}"
        case "$a" in
            y|Y) echo y; return;;
            n|N) echo n; return;;
            *) print_warning "Please enter y or n";;
        esac
  done
}

require_root() { 
    [[ ${EUID:-$(id -u)} -eq 0 ]] || { 
        print_error "This script must be run as root. Use: sudo bash $0"
        exit 1
    }
}

# ============================================================================
# MAIN UPDATE FLOW
# ============================================================================

log "=== WATTFOURCE Supabase Update Started ==="
log "Script: $0"
log "User: $(whoami)"

require_root
print_header

SUPABASE_DIR="/srv/supabase"
BACKUP_DIR="${SUPABASE_DIR}/backups"
BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Check if Supabase is installed
if [[ ! -d "$SUPABASE_DIR" ]]; then
    print_error "Supabase installation not found at $SUPABASE_DIR"
    print_info "Please run supabase-install.sh first"
    exit 1
fi

cd "$SUPABASE_DIR" || exit 1

# STEP 1: Pre-Update Check
print_step_header "1" "PRE-UPDATE CHECK"
echo

print_info "Checking Docker service..."
if ! systemctl is-active --quiet docker; then
    print_error "Docker service is not running"
    exit 1
fi
print_success "Docker is running"

print_info "Checking Supabase containers..."
if ! docker compose ps >/dev/null 2>&1; then
    print_error "Unable to access Supabase containers"
    exit 1
fi

CONTAINER_COUNT=$(docker compose ps -q | wc -l)
print_success "Found $CONTAINER_COUNT Supabase containers"

# STEP 2: Create Backups
print_step_header "2" "CREATING BACKUPS"
echo

mkdir -p "$BACKUP_DIR"

print_info "Backing up configuration files..."
cp .env "${BACKUP_DIR}/.env.${BACKUP_TIMESTAMP}" 2>/dev/null || true
cp docker-compose.yml "${BACKUP_DIR}/docker-compose.yml.${BACKUP_TIMESTAMP}" 2>/dev/null || true
cp docker-compose.override.yml "${BACKUP_DIR}/docker-compose.override.yml.${BACKUP_TIMESTAMP}" 2>/dev/null || true
print_success "Configuration backed up"

if [[ $(ask_yn "Create database backup? (recommended, may take a few minutes)" "y") = "y" ]]; then
    print_info "Creating database backup..."
    
    # Check if database is healthy
    if docker compose ps db | grep -q "healthy"; then
        BACKUP_FILE="${BACKUP_DIR}/db-backup-${BACKUP_TIMESTAMP}.dump"
        if docker compose exec -T db pg_dump -U postgres -Fc -d postgres > "$BACKUP_FILE" 2>>"$LOGFILE"; then
            BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            print_success "Database backed up: ${BACKUP_FILE} (${BACKUP_SIZE})"
            log "Database backup created: $BACKUP_FILE"
        else
            print_warning "Database backup failed (continuing anyway)"
            log "Database backup failed"
        fi
    else
        print_warning "Database not healthy, skipping backup"
    fi
else
    print_info "Skipping database backup"
fi

# STEP 3: System Package Updates
print_step_header "3" "SYSTEM PACKAGE UPDATES"
echo

if [[ $(ask_yn "Update system packages (Docker, tools)?" "y") = "y" ]]; then
    print_info "Updating package lists..."
    apt update >> "$LOGFILE" 2>&1 || true
    
    print_info "Checking for package updates..."
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
    
    if [[ "$UPGRADABLE" -gt 0 ]]; then
        print_info "Found $UPGRADABLE upgradable packages"
        if [[ $(ask_yn "Install system updates?" "y") = "y" ]]; then
            print_info "Upgrading packages (this may take a few minutes)..."
            apt upgrade -y >> "$LOGFILE" 2>&1 || {
                print_warning "Some package updates failed (check log)"
            }
            print_success "System packages updated"
        fi
    else
        print_success "All system packages are up to date"
    fi
else
    print_info "Skipping system package updates"
fi

# STEP 4: Check for Supabase Updates
print_step_header "4" "CHECKING SUPABASE UPDATES"
echo

print_info "Checking for new Docker images..."
echo

# Check which images have updates
IMAGES_TO_UPDATE=()
while IFS= read -r line; do
    if [[ "$line" =~ "Pulling" ]] || [[ "$line" =~ "newer" ]]; then
        IMAGES_TO_UPDATE+=("$line")
    fi
done < <(docker compose pull 2>&1 | tee -a "$LOGFILE")

if [[ ${#IMAGES_TO_UPDATE[@]} -gt 0 ]]; then
    printf "${C_GREEN}Updates available!${C_RESET}\n"
    print_success "Found updates for ${#IMAGES_TO_UPDATE[@]} service(s)"
else
    print_success "All Docker images are up to date"
    echo
    print_info "No Supabase updates available"
    
    if [[ $(ask_yn "Re-deploy containers anyway?" "n") = "n" ]]; then
        echo
        printf "${C_GREEN}✓ Update complete. No changes needed.${C_RESET}\n\n"
        exit 0
    fi
fi

# STEP 5: Apply Updates
print_step_header "5" "APPLYING UPDATES"
echo

print_info "Current container status:"
docker compose ps

echo
if [[ $(ask_yn "Apply updates and restart containers?" "y") = "n" ]]; then
    print_warning "Update cancelled by user"
    exit 0
fi

print_info "Redeploying Supabase services..."
echo

# Recreate containers with new images
if docker compose up -d >> "$LOGFILE" 2>&1; then
    print_success "Containers updated successfully"
else
    print_error "Container update failed!"
    print_info "Check logs: $LOGFILE"
    print_info "Rollback with: cd $SUPABASE_DIR && docker compose down && docker compose up -d"
    exit 1
fi

# Wait for services to stabilize
print_info "Waiting for services to start..."
sleep 15

# STEP 6: Health Check
print_step_header "6" "HEALTH CHECK"
echo

print_info "Checking container health..."
echo

UNHEALTHY=0
HEALTHY_COUNT=0
TOTAL_COUNT=0

while IFS= read -r line; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    CONTAINER=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{print $NF}')
    
    if echo "$STATUS" | grep -q "healthy"; then
        printf "${C_GREEN}✓${C_RESET} %s: healthy\n" "$CONTAINER"
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
    elif echo "$STATUS" | grep -q "unhealthy"; then
        printf "${C_RED}✗${C_RESET} %s: unhealthy\n" "$CONTAINER"
        UNHEALTHY=$((UNHEALTHY + 1))
    else
        printf "${C_CYAN}◉${C_RESET} %s: %s\n" "$CONTAINER" "$STATUS"
    fi
done < <(docker compose ps --format "{{.Name}} {{.Status}}")

echo

if [[ $UNHEALTHY -gt 0 ]]; then
    print_warning "$UNHEALTHY container(s) unhealthy"
    print_info "Check logs with: cd $SUPABASE_DIR && docker compose logs <container-name>"
else
    print_success "All containers healthy ($HEALTHY_COUNT/$TOTAL_COUNT)"
fi

# STEP 7: Cleanup
print_step_header "7" "CLEANUP"
echo

if [[ $(ask_yn "Remove old Docker images to free up space?" "y") = "y" ]]; then
    print_info "Removing unused images..."
    REMOVED=$(docker image prune -f 2>&1 | grep "deleted" | wc -l || echo "0")
    if [[ "$REMOVED" -gt 0 ]]; then
        print_success "Removed $REMOVED unused image(s)"
    else
        print_success "No unused images to remove"
    fi
fi

# Cleanup old backups (keep last 5)
print_info "Managing backup files..."
cd "$BACKUP_DIR" || true
BACKUP_COUNT=$(ls -1 db-backup-*.dump 2>/dev/null | wc -l || echo "0")
if [[ "$BACKUP_COUNT" -gt 5 ]]; then
    print_info "Keeping 5 most recent backups, removing $((BACKUP_COUNT - 5)) old backup(s)"
    ls -t db-backup-*.dump | tail -n +6 | xargs rm -f 2>/dev/null || true
    print_success "Old backups cleaned up"
else
    print_success "Backup count OK ($BACKUP_COUNT backups)"
fi

cd "$SUPABASE_DIR" || exit 1

# STEP 8: Summary
log "=== Update completed successfully ==="

echo
printf "${C_GREEN}══════════════════════════════════════════════════════════════════${C_RESET}\n"
printf "${C_GREEN}✓ Update Complete!${C_RESET}\n"
printf "${C_GREEN}══════════════════════════════════════════════════════════════════${C_RESET}\n\n"

printf "${C_WHITE}Summary:${C_RESET}\n"
printf "  Containers:     ${C_CYAN}%d healthy / %d total${C_RESET}\n" "$HEALTHY_COUNT" "$TOTAL_COUNT"
printf "  Backups:        ${C_CYAN}%s${C_RESET}\n" "$BACKUP_DIR"
printf "  Update Log:     ${C_CYAN}%s${C_RESET}\n" "$LOGFILE"
echo

printf "${C_WHITE}Useful Commands:${C_RESET}\n"
printf "  Check status:   ${C_CYAN}cd %s && docker compose ps${C_RESET}\n" "$SUPABASE_DIR"
printf "  View logs:      ${C_CYAN}cd %s && docker compose logs -f${C_RESET}\n" "$SUPABASE_DIR"
printf "  Restart all:    ${C_CYAN}cd %s && docker compose restart${C_RESET}\n" "$SUPABASE_DIR"
echo

printf "${C_CYAN}If you encounter issues:${C_RESET}\n"
printf "  1. Check container logs for errors\n"
printf "  2. Restore backup: cat %s/db-backup-*.dump | docker compose exec -T db pg_restore -U postgres -d postgres\n" "$BACKUP_DIR"
printf "  3. Restore config: cp %s/.env.* %s/.env\n" "$BACKUP_DIR" "$SUPABASE_DIR"
echo

