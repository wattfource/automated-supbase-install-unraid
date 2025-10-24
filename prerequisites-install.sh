#!/usr/bin/env bash
# ============================================================================
# PREREQUISITES INSTALLER FOR SUPABASE
# Installs Git, Docker, and Docker Compose (latest stable versions)
# Compatible with Supabase self-hosted stack
# ============================================================================
set -euo pipefail

# Minimum version requirements (for reference)
# Docker: 20.10.0+ recommended
# Docker Compose: v2.x (plugin format) required
# Git: 2.x

# Get script directory for log file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${SCRIPT_DIR}/prerequisites-install-$(date +%Y%m%d-%H%M%S).log"

# Color definitions
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"
C_RESET="\033[0m"

# Logging function
log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE" >/dev/null
}

# Display functions
print_header() {
    clear
    printf "${C_CYAN}WATTFOURCE${C_RESET} — Prerequisites Installation\n"
    printf "Log: %s\n\n" "$LOGFILE"
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

# Progress spinner
show_spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    printf "${C_CYAN}⟳${C_RESET} %s " "$msg"
    
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\b${spin:$i:1}"
        sleep 0.1
    done
    
    wait "$pid"
    local status=$?
    
    if [ $status -eq 0 ]; then
        printf "\b${C_GREEN}✓${C_RESET}\n"
    else
        printf "\b${C_RED}✗${C_RESET}\n"
        print_error "Command failed. Check $LOGFILE for details."
        return $status
    fi
}

# Execute command silently with spinner
exec_with_spinner() {
    local msg="$1"
    shift
    log "Executing: $*"
    
    # Run command in background, capture exit status properly
    set +e  # Temporarily disable exit on error
    "$@" >> "$LOGFILE" 2>&1 &
    local bg_pid=$!
    show_spinner $bg_pid "$msg"
    local exit_code=$?
    set -e  # Re-enable exit on error
    
    if [ $exit_code -ne 0 ]; then
        print_error "Command failed with exit code $exit_code"
        print_error "Check log file for details: $LOGFILE"
        print_error "Last 10 lines of log:"
        tail -n 10 "$LOGFILE" >&2 || true
        return $exit_code
    fi
    
    return 0
}

# Root check
require_root() { 
    [[ ${EUID:-$(id -u)} -eq 0 ]] || { 
        print_error "This script must be run as root. Use: sudo -i"
        exit 1
    }
}

#==============================================================================
# MAIN INSTALLATION
#==============================================================================

log "=== Prerequisites Installation Started ==="
log "Script: $0"
log "User: $(whoami)"
log "Working Directory: $(pwd)"

require_root
print_header

# Update package lists
exec_with_spinner "Updating package lists..." apt update || {
    print_error "Failed to update package lists"
    exit 1
}

# Install basic tools
printf "\n${C_WHITE}Installing Basic Tools${C_RESET}\n"
echo

exec_with_spinner "Installing system tools..." apt install -y curl gpg jq openssl git || {
    print_error "Failed to install system tools"
    exit 1
}
print_success "System tools installed"

# Install Docker
printf "\n${C_WHITE}Installing Docker Engine${C_RESET}\n"
echo

exec_with_spinner "Adding Docker repository..." bash -c '
    set -euo pipefail
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
    apt update
' || {
    print_error "Failed to add Docker repository"
    exit 1
}

exec_with_spinner "Installing Docker packages..." apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
    print_error "Docker installation failed"
    exit 1
}

exec_with_spinner "Enabling Docker service..." systemctl enable docker || {
    print_error "Failed to enable Docker service"
    exit 1
}

exec_with_spinner "Starting Docker service..." systemctl start docker || {
    print_error "Failed to start Docker service"
    exit 1
}

# Wait for Docker daemon to be fully ready
print_info "Waiting for Docker daemon to be ready..."
for i in {1..30}; do
    if docker info >/dev/null 2>&1; then
        print_success "Docker daemon is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "Docker daemon did not become ready in time"
        print_info "Try running: sudo systemctl status docker"
        exit 1
    fi
    sleep 1
done

print_success "Docker Engine installed and running"

# Verify installations
printf "\n${C_WHITE}Verifying Installations${C_RESET}\n"
echo

GIT_VERSION=$(git --version | grep -oP '\d+\.\d+\.\d+' | head -1)
DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
COMPOSE_VERSION=$(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)

print_success "Git v${GIT_VERSION}"
print_success "Docker v${DOCKER_VERSION}"
print_success "Docker Compose v${COMPOSE_VERSION}"

# Completion
log "=== Prerequisites installation completed successfully ==="
log "Git: $GIT_VERSION | Docker: $DOCKER_VERSION | Compose: $COMPOSE_VERSION"

printf "\n${C_GREEN}✓ Prerequisites installed successfully!${C_RESET}\n\n"
printf "${C_WHITE}Installed Components:${C_RESET}\n"
printf "  • Git ${C_CYAN}v${GIT_VERSION}${C_RESET}\n"
printf "  • Docker Engine ${C_CYAN}v${DOCKER_VERSION}${C_RESET}\n"
printf "  • Docker Compose ${C_CYAN}v${COMPOSE_VERSION}${C_RESET} (v2 plugin format)\n"
printf "  • System tools (curl, gpg, jq, openssl)\n\n"

printf "${C_WHITE}Compatibility Status:${C_RESET}\n"
printf "  ${C_GREEN}✓${C_RESET} Supabase self-hosted stack: ${C_GREEN}Compatible${C_RESET}\n\n"

printf "${C_CYAN}Installation log: ${C_WHITE}$LOGFILE${C_RESET}\n\n"
printf "${C_GREEN}✓ Ready to run Supabase installation!${C_RESET}\n\n"

