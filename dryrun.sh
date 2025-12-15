#!/bin/bash

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}!!! DRY RUN MODE ACTIVE !!!${NC}"
echo "No files will be written. No containers will be started."
echo "-----------------------------------------------------"

# --- 0. MOCK LOCATION ENFORCER ---
# In the real script, this runs automatically. 
# Here, we ask if you want to test that specific logic.
REQUIRED_DIR="$HOME/servarr-stack"

echo -e "${BLUE}DRY RUN TEST:${NC} Do you want to simulate running from the WRONG directory?"
read -p "Simulate wrong location? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    CURRENT_DIR="/tmp/downloads/servarr-stack" # Fake wrong location
    echo "========================================"
    echo -e "${RED}   LOCATION ERROR${NC}"
    echo "========================================"
    echo "To ensure permissions work correctly, this stack MUST be installed at:"
    echo -e "${YELLOW}$REQUIRED_DIR${NC}"
    echo ""
    echo "You are currently at:"
    echo -e "${RED}$CURRENT_DIR${NC}"
    echo ""
    
    echo "I can move this entire folder to the correct location for you."
    read -p "Move folder and exit? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}DRY RUN:${NC} Would run: mv $CURRENT_DIR $REQUIRED_DIR"
        echo -e "${GREEN}Move complete (Simulated).${NC}"
        echo "Please run the following commands to continue:"
        echo -e "${YELLOW}cd $REQUIRED_DIR && ./install.sh${NC}"
        echo "Exiting now (Simulating script restart)."
        exit 0
    else
        echo -e "${RED}Installation Aborted.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Location Check Passed (Simulated).${NC}"
    STACK_DIR="."
    DISPLAY_DIR="Current Directory"
fi

# --- 1. MOCK PRE-FLIGHT CHECK ---
if [ -f "$STACK_DIR/.env" ]; then
    echo -e "${BLUE}DRY RUN:${NC} Found existing .env (Simulated). In real run, script would EXIT."
else
    echo -e "${BLUE}DRY RUN:${NC} No existing .env found. Proceeding."
fi

echo "========================================"
echo "   SERVARR VPN STACK INSTALLER"
echo "========================================"

prompt_user() {
    local var_name=$1
    local default_val=$2
    local desc=$3
    echo -e "\n--- $var_name ---"
    echo -e "$desc"
    echo -e "Default: ${YELLOW}$default_val${NC}"
    read -p "Enter value (or press ENTER to use default): " input
    if [ -z "$input" ]; then USER_INPUT="$default_val"; else USER_INPUT="$input"; fi
}

# --- CALCULATE DEFAULTS ---
DEFAULT_PUID=$(id -u)
DEFAULT_PGID=$(id -g)
DEFAULT_TZ="America/New_York"

# --- ENFORCED PATHS ---
VAL_CONFIG="$HOME/servarr-stack/.config"
VAL_MEDIA="$HOME/servarr-stack/data"

echo -e "\n--- STORAGE LOCATIONS (ENFORCED) ---"
echo "To ensure permissions and safety, paths are set automatically:"
echo -e "Config: ${BLUE}$VAL_CONFIG${NC}"
echo -e "Data:   ${BLUE}$VAL_MEDIA${NC}"

# --- GATHER INPUTS ---
prompt_user "PUID" "$DEFAULT_PUID" "User ID to run containers as."
VAL_PUID=$USER_INPUT

prompt_user "PGID" "$DEFAULT_PGID" "Group ID to run containers as."
VAL_PGID=$USER_INPUT

prompt_user "TZ" "$DEFAULT_TZ" "System Timezone"
VAL_TZ=$USER_INPUT

# Network - REAL DETECTION LOGIC
echo -e "\n${BLUE}DRY RUN:${NC} Attempting to detect local subnet..."
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
DETECTED_SUBNET=$(ip route | grep "dev $DEFAULT_IFACE" | grep -v "^default" | awk '{print $1}' | head -n 1)

if [ -z "$DETECTED_SUBNET" ]; then
    DEFAULT_SUBNET="192.168.1.0/24"
    echo -e "${RED}⚠️  WARNING: Could not detect your local subnet.${NC}"
    echo -e "Defaulting to guess: ${YELLOW}$DEFAULT_SUBNET${NC}"
    read -p "Enter your Subnet (CIDR format): " input
    if [ -z "$input" ]; then VAL_SUBNET="$DEFAULT_SUBNET"; else VAL_SUBNET="$input"; fi
else
    echo -e "${GREEN}Success! Detected: $DETECTED_SUBNET${NC}"
    prompt_user "LOCAL_SUBNET" "$DETECTED_SUBNET" "Your LAN Subnet. Required for WebUI access."
    VAL_SUBNET=$USER_INPUT
fi

# VPN Selection
echo -e "\n--- VPN PROVIDER ---"
echo "Select your VPN Service Provider:"
PS3='Please enter your choice (number): '
options=("airvpn" "cyberghost" "expressvpn" "fastestvpn" "hidemyass" "ipvanish" "ivpn" "mullvad" "nordvpn" "perfectprivacy" "privado" "privateinternetaccess" "privatevpn" "protonvpn" "purevpn" "surfshark" "tororg" "torguard" "vpnunlimited" "vyprvpn" "windscribe" "Other/Custom")
select opt in "${options[@]}"
do
    case $opt in
        "Other/Custom")
            read -p "Enter your provider name manually (e.g. custom): " VAL_PROVIDER
            break
            ;;
        *)
            if [ -n "$opt" ]; then VAL_PROVIDER=$opt; break; else echo "Invalid option."; fi
            ;;
    esac
done
echo -e "${GREEN}Selected Provider: $VAL_PROVIDER${NC}"

prompt_user "SERVER_COUNTRIES" "Netherlands" "VPN Server Country"
VAL_COUNTRIES=$USER_INPUT

echo -e "\n--- VPN PROTOCOL ---"
echo "1) OpenVPN (Standard)"
echo "2) WireGuard (Faster)"
read -p "Select [1-2]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[2]$ ]]; then
    VAL_TYPE="wireguard"
    echo -e "${GREEN}Selected: WireGuard${NC}"
    read -p "WireGuard Private Key: " VAL_WG_KEY
    read -p "WireGuard IPv4 Address (Optional): " VAL_WG_ADDR
    VAL_VPN_USER=""
    VAL_VPN_PASS=""
else
    VAL_TYPE="openvpn"
    echo -e "${GREEN}Selected: OpenVPN${NC}"
    read -p "Enter VPN Username: " VAL_VPN_USER
    read -s -p "Enter VPN Password: " VAL_VPN_PASS
    echo ""
    VAL_WG_KEY=""
    VAL_WG_ADDR=""
fi

prompt_user "WEBUI_PORT" "8091" "qBittorrent WebUI Port"
VAL_WEBUI=$USER_INPUT
prompt_user "TORRENTING_PORT" "6881" "qBittorrent Traffic Port"
VAL_TORRENT=$USER_INPUT

# --- MOCK WRITE .ENV ---
echo -e "\n${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW} DRY RUN: GENERATED .ENV CONTENT CHECK ${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"
cat <<EOF
# --- GENERATED BY INSTALL SCRIPT ---
PUID=$VAL_PUID
PGID=$VAL_PGID
TZ=$VAL_TZ
CONFIG_ROOT=$VAL_CONFIG
MEDIA_ROOT=$VAL_MEDIA
LOCAL_SUBNET=$VAL_SUBNET
VPN_SERVICE_PROVIDER=$VAL_PROVIDER
VPN_TYPE=$VAL_TYPE
SERVER_COUNTRIES=$VAL_COUNTRIES
OPENVPN_USER=$VAL_VPN_USER
OPENVPN_PASSWORD=$VAL_VPN_PASS
WIREGUARD_PRIVATE_KEY=$VAL_WG_KEY
WIREGUARD_ADDRESSES=$VAL_WG_ADDR
WEBUI_PORT=$VAL_WEBUI
TORRENTING_PORT=$VAL_TORRENT
EOF
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${BLUE}DRY RUN:${NC} File would be saved to: $STACK_DIR/.env"

# --- MOCK DIRECTORIES ---
echo -e "\n--- CREATE DIRECTORIES ---"
echo -e "${BLUE}DRY RUN:${NC} Would mkdir -p $VAL_CONFIG/{jellyfin,prowlarr,radarr,sonarr,qbittorrent}"
echo -e "${BLUE}DRY RUN:${NC} Would mkdir -p $VAL_MEDIA/{torrents,media}"
echo -e "${BLUE}DRY RUN:${NC} Would mkdir -p $VAL_MEDIA/media/{movies,tv}"

# --- MOCK START ---
echo "========================================"
echo "   SETUP COMPLETE"
echo "========================================"
read -p "Start the stack now? (y/n): " -n 1 -r
echo
if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}DRY RUN:${NC} Would run: docker compose up -d"
else
    echo "Skipping start."
fi