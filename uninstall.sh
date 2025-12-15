#!/bin/bash

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- HELPER: ERROR CHECKER ---
# Usage: check_status $? "Context Message"
check_status() {
    if [ $1 -ne 0 ]; then
        echo -e "${RED}ERROR: $2 failed!${NC}"
        echo "The previous step encountered an error."
        read -p "Do you want to (c)ontinue anyway or (a)bort? (c/a): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Cc]$ ]]; then
            echo "Aborting uninstall."
            exit 1
        fi
        echo -e "Resuming uninstall despite errors...\n"
    else
        echo -e "${GREEN}Success: $2${NC}"
    fi
}

# --- 1. SMART DIRECTORY DETECTION ---
if [ -f "docker-compose.yml" ]; then
    STACK_DIR="."
elif [ -f "servarr/docker-compose.yml" ]; then
    STACK_DIR="servarr"
else
    echo -e "${RED}ERROR: Could not find 'docker-compose.yml'.${NC}"
    echo "Please ensure you are in the 'servarr-stack' folder."
    exit 1
fi

# 0. Safety Check: Ensure script is NOT run as root
if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}Please do not run this script as root (sudo).${NC}"
  echo "Run it as your normal user. The script will ask for sudo when needed."
  exit 1
fi

# --- 2. PRE-FLIGHT CHECK: IS IT INSTALLED? ---
ENV_FILE="$STACK_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "========================================"
    echo -e "${RED}   STACK NOT FOUND${NC}"
    echo "========================================"
    echo "Could not find an '.env' file at $ENV_FILE."
    echo "This indicates the stack is not currently installed or configured."
    echo ""
    echo "Nothing to uninstall."
    exit 0
fi

# 1. Invalidate Sudo Cache
sudo -k

echo "========================================"
echo -e "${RED}   SERVARR VPN STACK UNINSTALLER${NC}"
echo "========================================"
echo -e "Detected Stack Directory: ${GREEN}$STACK_DIR${NC}"

# --- 3. READ VARIABLES FROM .ENV ---
DETECTED_CONFIG=$(grep "^CONFIG_ROOT=" "$ENV_FILE" | cut -d '=' -f2)
DETECTED_MEDIA=$(grep "^MEDIA_ROOT=" "$ENV_FILE" | cut -d '=' -f2)

if [ -z "$DETECTED_CONFIG" ] || [ -z "$DETECTED_MEDIA" ]; then
    echo -e "${RED}ERROR: .env file is missing CONFIG_ROOT or MEDIA_ROOT variables.${NC}"
    echo "Aborting uninstall for safety."
    exit 1
fi

# Adjust relative config path to be relative to where the script is running
# If CONFIG_ROOT is "./config", and STACK_DIR is "servarr", we need "servarr/config"
if [[ "$DETECTED_CONFIG" == ./* ]]; then
    REAL_CONFIG_PATH="$STACK_DIR/${DETECTED_CONFIG#./}"
else
    REAL_CONFIG_PATH="$DETECTED_CONFIG"
fi

# --- 4. EXPLAIN ACTIONS TO USER ---
echo "This script will perform the following actions:"
echo " 1. STOP and REMOVE all Docker containers associated with this stack."
echo " 2. OFFER to remove Docker images and networks used by this stack."
echo " 3. DELETE the '.env' file containing your credentials."
echo " 4. OFFER to delete your Configuration files ($REAL_CONFIG_PATH)."
echo " 5. OFFER to delete your Media/Data files ($DETECTED_MEDIA)."
echo ""
echo -e "${RED}SECURITY NOTICE:${NC}"
echo "For your safety, this script invalidates your sudo session."
echo "You will be required to enter your password manually for EACH destructive operation."
echo ""

read -p "Are you sure you want to proceed? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# --- 5. STOP DOCKER CONTAINERS ---
echo -e "\n--- STOPPING CONTAINERS ---"
# We enter the stack directory to run compose commands
pushd "$STACK_DIR" > /dev/null

if command -v docker &> /dev/null; then
    echo "Stopping and removing servarr containers..."
    docker compose down || (echo "Retrying with sudo..." && sudo docker compose down)
    check_status $? "Stopping containers"
else
    echo -e "${RED}WARNING: Docker command not found!${NC}"
    echo "We cannot stop containers if Docker is missing."
    read -p "Do you want to (c)ontinue anyway (to delete files) or (a)bort? (c/a): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Cc]$ ]]; then
        echo "Aborting uninstall."
        exit 1
    fi
fi
popd > /dev/null

# --- 6. CLEAN DOCKER ARTIFACTS ---
echo -e "\n--- CLEAN DOCKER IMAGES & NETWORKS ---"
echo "This will remove the specific Docker images downloaded for this stack."
echo "Default: No"
read -p "Remove Docker images and networks? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v docker &> /dev/null; then
        echo "Removing images..."
        docker image rm qmcgaw/gluetun jellyfin/jellyfin lscr.io/linuxserver/prowlarr ghcr.io/hotio/radarr ghcr.io/hotio/sonarr ghcr.io/flaresolverr/flaresolverr lscr.io/linuxserver/qbittorrent 2>/dev/null
        docker network prune -f 2>/dev/null
        echo -e "${GREEN}Docker cleanup complete.${NC}"
    else
        echo -e "${RED}Skipping: Docker not found.${NC}"
    fi
else
    echo "Skipping Docker image cleanup."
fi

# --- 7. REMOVE CONFIG FILES ---
echo -e "\n--- DELETE CONFIGURATION FILES ---"
echo "Target: $REAL_CONFIG_PATH"
echo -e "${RED}WARNING: This cannot be undone.${NC}"
echo "Default: No"
read -p "Delete configuration files? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "$REAL_CONFIG_PATH" ]; then
        sudo rm -rf "$REAL_CONFIG_PATH"
        check_status $? "Deleting config files"
    else
        echo "Config directory not found at $REAL_CONFIG_PATH. Skipping."
    fi
else
    echo "Skipping config deletion."
fi

# --- 8. REMOVE MEDIA/DATA ---
echo -e "\n--- DELETE MEDIA & DATA ---"
echo "Target: $DETECTED_MEDIA"
echo -e "${RED}CRITICAL WARNING: This will wipe your library.${NC}"
echo "Default: No"
read -p "Do you really want to delete your MEDIA/DATA folder? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "$DETECTED_MEDIA" ]; then
        sudo -k 
        echo -e "${RED}SECURITY CHECK: Password required to delete media library.${NC}"
        sudo rm -rf "$DETECTED_MEDIA"
        check_status $? "Deleting media library"
    else
        echo "Media directory not found at $DETECTED_MEDIA. Skipping."
    fi
else
    echo "Skipping media deletion."
fi

# --- 9. REMOVE .ENV FILE ---
echo -e "\n--- REMOVE ENVIRONMENT FILE ---"
rm "$ENV_FILE"
check_status $? "Removing .env file"

echo "========================================"
echo -e "${GREEN}   UNINSTALL COMPLETE${NC}"
echo "========================================"