# Automated Supabase Install for Unraid

An automated installer script for setting up Supabase on Unraid or other Debian-based systems. This script handles all dependencies including Docker and Git, and sets up a complete Supabase instance.

## Installation

### Method 1: Multi-Step Install (Recommended)

```bash
# 1) Become root
sudo -i

# 2) (Optional) basic updates
apt update && apt -y upgrade

# 3) Fetch the installer from GitHub and run it
cd /root
curl -fsSL -o supabase-install.sh \
  https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh
chmod +x supabase-install.sh
./supabase-install.sh
```

### Method 2: One-Liner Install

Run the installer directly from GitHub using process substitution:

```bash
sudo -i bash <(curl -fsSL https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh)
```

### Method 3: Using wget (if curl is not available)

```bash
sudo -i
apt update && apt -y install wget
cd /root
wget -O supabase-install.sh https://raw.githubusercontent.com/wattfource/automated-supbase-install-unraid/main/supabase-install.sh
chmod +x supabase-install.sh
./supabase-install.sh
```

## What the Script Does

The installer will automatically:
- Check for and install Docker if not present
- Check for and install Git if not present
- Clone the Supabase repository
- Set up the Supabase environment
- Start all required services

## Requirements

- Debian-based system (Unraid, Ubuntu, Debian, etc.)
- Root or sudo access
- Internet connection

## Notes

- The script handles all dependencies automatically - you don't need to pre-install Docker or Git
- All installation occurs in `/root/supabase` by default
- Make sure you have sufficient disk space for Docker containers