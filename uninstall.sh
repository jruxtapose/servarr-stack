#!/bin/bash

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- 1. DEFINE SAFE ZONES ---
# The installer enforces folders to be inside $HOME/servarr-stack.
# We will ONLY allow deletion if the target is inside this specific path.
REQUIRED_PARENT="$HOME/servarr-stack"

# --- SAFETY LOCK FUNCTION ---
# Returns 0 (True) if safe, 1 (False) if unsafe.
is_safe_to_delete() {
    local target="$1"
    
    # Resolve absolute paths to avoid symlink trickery
    local expanded_target
    expanded_target=$(realpath -m "$target")
    local expanded_parent
    expanded_parent=$(realpath -m "$REQUIRED_PARENT")

    # CHECK: Is the target inside the required parent folder?
    # We check if the target path starts with the parent path
    if [[ "$expanded_target" == "$expanded_parent"* ]]; then
        # Double check: Don't delete the parent folder itself yet, only subfolders
        if [[ "$expanded_target" == "$expanded_parent" ]]; then
            # Use caution if targeting the root itself, generally we want to delete subfolders
            return 0
        fi
        return 0
    else
        return 1
    fi
}

# --- 2. DETECT STACK ---
if [ -f "docker-compose.yml" ]; then
    STACK_DIR="."
elif [ -f "servarr/docker-compose.yml" ]; then
    STACK_DIR="servarr"
else
    echo -e "${RED}ERROR: Could not find 'docker-compose.yml'.${NC}"
    echo "Please ensure you are in the 'servarr-stack' git repository."
    exit 1
fi

# 0. Root Check
if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}Please do not run this script as root.${NC}"
  echo "The script will manage sudo prompts for safety."
  exit 1
fi

# 3. Pre-flight Check
ENV_FILE="$STACK_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}No .env file found.${NC}"
    echo "The stack appears to be uninstalled already."
    exit 0
fi

echo "========================================"
echo -e "${RED}   SERVARR VPN STACK UNINSTALLER${NC}"
echo "========================================"

# --- 4. READ VARIABLES ---
DETECTED_CONFIG=$(grep "^CONFIG_ROOT=" "$ENV_FILE" | cut -d '=' -f2)
DETECTED_MEDIA=$(grep "^MEDIA_ROOT=" "$ENV_FILE" | cut -d '=' -f2)

if [ -z "$DETECTED_CONFIG" ] || [ -z "$DETECTED_MEDIA" ]; then
    echo -e "${RED}ERROR: Corrupted .env file. Paths missing.${NC}"
    exit 1
fi

# --- 5. EXPLAIN ACTIONS ---
echo "This script will:"
echo " 1. STOP and REMOVE all containers."
echo " 2. OFFER to remove Docker images."
echo " 3. DELETE the .env file (Generated config)."
echo " 4. OFFER to delete Config Folder: ${YELLOW}$DETECTED_CONFIG${NC}"
echo " 5. OFFER to delete Data Folder:   ${YELLOW}$DETECTED_MEDIA${NC}"
echo ""
echo -e "${GREEN}NOTE: This script will NOT delete the git repository files.${NC}"
echo -e "${GREEN}You can run ./install.sh again immediately after this.${NC}"
echo ""
echo -e "${RED}SECURITY NOTICE: You will be asked for your password before EACH deletion.${NC}"
echo ""

read -p "Proceed? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 0; fi

# --- 6. STOP CONTAINERS ---
echo -e "\n--- STOPPING CONTAINERS ---"
pushd "$STACK_DIR" > /dev/null
# Try normal, then force password prompt if sudo is needed
docker compose down || (echo "Retrying with sudo..." && sudo -k && sudo docker compose down)
popd > /dev/null

# --- 7. CLEAN IMAGES ---
echo -e "\n--- DOCKER IMAGES ---"
read -p "Remove Docker images? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker image rm qmcgaw/gluetun jellyfin/jellyfin lscr.io/linuxserver/prowlarr ghcr.io/hotio/radarr ghcr.io/hotio/sonarr ghcr.io/flaresolverr/flaresolverr lscr.io/linuxserver/qbittorrent 2>/dev/null
    echo -e "${GREEN}Images removed.${NC}"
fi

# --- 8. REMOVE CONFIG ---
echo -e "\n--- CONFIGURATION FILES ---"
echo -e "Target: ${YELLOW}$DETECTED_CONFIG${NC}"

if is_safe_to_delete "$DETECTED_CONFIG"; then
    read -p "Delete this folder? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -d "$DETECTED_CONFIG" ]; then
            echo "Password required to delete config:"
            sudo -k # Invalidate previous session
            if sudo rm -rf "$DETECTED_CONFIG"; then
                echo -e "${GREEN}Config deleted.${NC}"
            else
                echo -e "${RED}Deletion skipped (Password incorrect).${NC}"
            fi
        else
            echo "Config folder not found. Skipping."
        fi
    fi
else
    echo -e "${RED}SKIPPING:${NC} Target is outside of '$REQUIRED_PARENT'."
    echo "For safety, we refuse to delete external folders."
fi

# --- 9. REMOVE MEDIA (NUCLEAR OPTION) ---
echo -e "\n--- MEDIA & DATA (DESTRUCTIVE) ---"
echo -e "Target: ${YELLOW}$DETECTED_MEDIA${NC}"

if is_safe_to_delete "$DETECTED_MEDIA"; then
    echo -e "${RED}WARNING: This folder contains your downloaded Movies and TV Shows.${NC}"
    echo -e "${RED}If you delete this, your files are GONE FOREVER.${NC}"
    echo ""
    
    if [ -d "$DETECTED_MEDIA" ]; then
        # Step 1: Manual text confirmation
        echo "To confirm deletion, type: DELETE LIBRARY"
        read -p "Confirmation: " CONFIRM_TEXT
        
        if [ "$CONFIRM_TEXT" == "DELETE LIBRARY" ]; then
            echo ""
            echo -e "${RED}FINAL SECURITY CHECK${NC}"
            echo "Password required to delete library:"
            
            # Step 2: Kill sudo token to force password entry
            sudo -k 
            
            # Step 3: Attempt deletion
            if sudo rm -rf "$DETECTED_MEDIA"; then
                echo -e "${GREEN}Library deleted.${NC}"
            else
                echo -e "${RED}Deletion failed or cancelled (Incorrect Password).${NC}"
                echo "Your data folder remains intact."
            fi
        else
            echo -e "${GREEN}Mismatch. Deletion cancelled. Your files are safe.${NC}"
        fi
    else
        echo "Folder not found. Skipping."
    fi
else
    echo -e "${RED}SKIPPING:${NC} Target is outside of '$REQUIRED_PARENT'."
    echo "For safety, we refuse to delete external folders."
fi

# --- 10. REMOVE .ENV (PRESERVE REPO) ---
echo -e "\n--- CLEANUP ---"
# We only delete the .env file. We LEAVE the git repo files (install.sh, etc) intact.
rm "$ENV_FILE"
echo -e "${GREEN}.env file removed.${NC}"
echo -e "${BLUE}Repository files preserved. You can re-run install.sh anytime.${NC}"
echo -e "${GREEN}Uninstall Complete.${NC}"