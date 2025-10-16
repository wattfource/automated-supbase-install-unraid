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

# Clean up broken Docker configurations from previous failed installations
cleanup_docker_config() {
    local cleaned=0
    
    # Check for broken Docker repository (repository exists but GPG key doesn't)
    if [[ -f /etc/apt/sources.list.d/docker.list ]] && [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        log "Detected broken Docker repository configuration from previous attempt"
        print_warning "Cleaning up broken Docker repository configuration..."
        rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
        cleaned=1
    fi
    
    # Check for orphaned Docker keyring directory
    if [[ -d /etc/apt/keyrings ]] && [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        # Remove only if it's empty or contains broken Docker keys
        if [[ -z "$(ls -A /etc/apt/keyrings 2>/dev/null)" ]]; then
            rmdir /etc/apt/keyrings 2>/dev/null || true
        fi
    fi
    
    # If we cleaned anything, update apt cache
    if [[ $cleaned -eq 1 ]]; then
        log "Running apt update to refresh package lists..."
        apt update >> "$LOGFILE" 2>&1 || {
            log "Warning: apt update failed, but continuing anyway"
        }
        print_success "Cleanup complete"
    fi
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

# Clean up any broken configurations
cleanup_docker_config

# Update package lists
print_info "Updating package lists..."
exec_with_spinner "Running apt update..." apt update || {
    print_error "Failed to update package lists"
    exit 1
}

# Install basic tools
printf "\n${C_WHITE}Installing Basic Tools${C_RESET}\n"
echo

for cmd in curl gpg jq openssl git; do
    if ! command -v $cmd >/dev/null 2>&1; then
        exec_with_spinner "Installing $cmd..." apt install -y $cmd || {
            print_error "Failed to install $cmd"
            exit 1
        }
    else
        print_success "$cmd already installed"
    fi
done

# Install Docker
printf "\n${C_WHITE}Installing Docker Engine${C_RESET}\n"
echo

if ! command -v docker >/dev/null 2>&1; then
    print_info "Installing Docker Engine..."
    
    exec_with_spinner "Adding Docker repository..." bash -c '
        set -euo pipefail
        install -m 0755 -d /etc/apt/keyrings || exit 1
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || exit 1
        chmod a+r /etc/apt/keyrings/docker.gpg || exit 1
        . /etc/os-release || exit 1
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list || exit 1
        apt update || exit 1
    ' || {
        print_error "Failed to add Docker repository. Please check your internet connection."
        exit 1
    }
    
    exec_with_spinner "Installing Docker packages..." bash -c '
        set -euo pipefail
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || exit 1
    ' || {
        print_error "Docker installation failed."
        print_error "You may need to install Docker manually: https://docs.docker.com/engine/install/debian/"
        exit 1
    }
    
    exec_with_spinner "Enabling Docker service..." systemctl enable --now docker || {
        print_error "Failed to start Docker service"
        exit 1
    }
    
    print_success "Docker Engine installed successfully"
else
    print_success "Docker already installed"
    
    # Verify Docker Compose plugin is installed
    if ! docker compose version >/dev/null 2>&1; then
        print_warning "Docker Compose plugin not found, installing..."
        exec_with_spinner "Installing Docker Compose plugin..." apt install -y docker-compose-plugin || {
            print_error "Failed to install Docker Compose plugin"
            exit 1
        }
    else
        print_success "Docker Compose already installed"
    fi
fi

# Verify installations and compatibility
printf "\n${C_WHITE}Verifying Installations & Compatibility${C_RESET}\n"
echo

# Get versions
GIT_VERSION=$(git --version | grep -oP '\d+\.\d+\.\d+' | head -1)
DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
COMPOSE_VERSION=$(docker compose version | grep -oP '\d+\.\d+\.\d+' | head -1)

print_info "Git version: $GIT_VERSION"
print_info "Docker version: $DOCKER_VERSION"
print_info "Docker Compose version: $COMPOSE_VERSION"

# Verify Docker Compose v2 format (plugin-based)
if docker compose version >/dev/null 2>&1; then
    print_success "Docker Compose v2 (plugin) verified"
else
    print_error "Docker Compose plugin not working correctly"
    exit 1
fi

# Test Docker daemon
if docker ps >/dev/null 2>&1; then
    print_success "Docker daemon running"
else
    print_warning "Docker daemon may not be running. Starting..."
    systemctl start docker || {
        print_error "Failed to start Docker daemon"
        exit 1
    }
fi

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

