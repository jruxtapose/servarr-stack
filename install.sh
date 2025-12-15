#!/bin/bash

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 0. LOCATION ENFORCER ---
CURRENT_DIR=$(pwd)
REQUIRED_DIR="$HOME/servarr-stack"
ABS_CURRENT=$(realpath "$CURRENT_DIR")
ABS_REQUIRED=$(realpath -m "$REQUIRED_DIR")

if [[ "$ABS_CURRENT" != "$ABS_REQUIRED" ]]; then
    echo "========================================"
    echo -e "${RED}   LOCATION ERROR${NC}"
    echo "========================================"
    echo "To ensure permissions work correctly, this stack MUST be installed at:"
    echo -e "${YELLOW}$REQUIRED_DIR${NC}"
    echo ""
    echo "You are currently at:"
    echo -e "${RED}$CURRENT_DIR${NC}"
    echo ""

    if [ -d "$REQUIRED_DIR" ]; then
        echo -e "${RED}Target folder '$REQUIRED_DIR' already exists!${NC}"
        echo "Please fix your directory structure manually."
        exit 1
    fi

    echo "I can move this entire folder to the correct location for you."
    read -p "Move folder and exit? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Moving files..."
        mv "$ABS_CURRENT" "$REQUIRED_DIR"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Success.${NC}"
            echo "------------------------------------------------"
            echo "Please run the following commands to continue:"
            echo -e "${YELLOW}cd $REQUIRED_DIR${NC}"
            echo -e "${YELLOW}./install.sh${NC}"
            echo "------------------------------------------------"
            exit 0
        else
            echo -e "${RED}Move failed. Please move manually.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Installation Aborted.${NC}"
        exit 1
    fi
fi

# --- 1. SMART DIRECTORY DETECTION ---
if [ -f "docker-compose.yml" ]; then
    STACK_DIR="."
    DISPLAY_DIR="Current Directory"
elif [ -f "servarr/docker-compose.yml" ]; then
    STACK_DIR="servarr"
    DISPLAY_DIR="./servarr"
else
    echo -e "${RED}ERROR: Could not find 'docker-compose.yml'.${NC}"
    echo "Please ensure this script is in the 'servarr-stack' folder."
    exit 1
fi

# --- 2. PRE-FLIGHT CHECK ---
if [ -f "$STACK_DIR/.env" ]; then
    echo "========================================"
    echo -e "${RED}   STACK ALREADY INSTALLED${NC}"
    echo "========================================"
    echo "An '.env' file was found. Run './uninstall.sh' first."
    exit 1
fi

echo "========================================"
echo "   SERVARR VPN STACK INSTALLER"
echo "========================================"

# --- HELPER FUNCTION FOR PROMPTS ---
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

# 0. Safety Check
if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}Please do not run this script as root (sudo).${NC}"
  exit 1
fi

# 3. Docker Check
if ! command -v docker &> /dev/null; then
    echo "Docker is not currently installed."
    read -p "Install Docker automatically? (y/n): " -n 1 -r
    echo 
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo usermod -aG docker $USER
        echo -e "${GREEN}Docker installed. Log out and back in.${NC}"
    else
        echo -e "${RED}Docker is required. Exiting.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Docker is already installed.${NC}"
fi

echo "========================================"
echo "   CONFIGURATION SETUP"
echo "========================================"

# --- DEFAULTS ---
DEFAULT_PUID=$(id -u)
DEFAULT_PGID=$(id -g)
DEFAULT_TZ="America/New_York"
VAL_CONFIG="$HOME/servarr-stack/.config"
VAL_MEDIA="$HOME/servarr-stack/data"

echo -e "\n--- STORAGE LOCATIONS (ENFORCED) ---"
echo -e "Config: ${BLUE}$VAL_CONFIG${NC}"
echo -e "Data:   ${BLUE}$VAL_MEDIA${NC}"

# --- GATHER INPUTS ---
prompt_user "PUID" "$DEFAULT_PUID" "User ID to run containers as."
VAL_PUID=$USER_INPUT
prompt_user "PGID" "$DEFAULT_PGID" "Group ID to run containers as."
VAL_PGID=$USER_INPUT
prompt_user "TZ" "$DEFAULT_TZ" "System Timezone"
VAL_TZ=$USER_INPUT

# Network
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
DETECTED_SUBNET=$(ip route | grep "dev $DEFAULT_IFACE" | grep -v "^default" | awk '{print $1}' | head -n 1)

if [ -z "$DETECTED_SUBNET" ]; then
    DEFAULT_SUBNET="192.168.1.0/24"
    echo -e "\n--- LOCAL_SUBNET ---"
    echo -e "${RED}⚠️  WARNING: Could not detect subnet.${NC}"
    read -p "Enter your Subnet (CIDR format): " input
    if [ -z "$input" ]; then VAL_SUBNET="$DEFAULT_SUBNET"; else VAL_SUBNET="$input"; fi
else
    prompt_user "LOCAL_SUBNET" "$DETECTED_SUBNET" "Your LAN Subnet."
    VAL_SUBNET=$USER_INPUT
fi

# VPN
echo -e "\n--- VPN PROVIDER ---"
PS3='Select VPN Provider: '
options=("airvpn" "cyberghost" "expressvpn" "fastestvpn" "hidemyass" "ipvanish" "ivpn" "mullvad" "nordvpn" "perfectprivacy" "privado" "privateinternetaccess" "privatevpn" "protonvpn" "purevpn" "surfshark" "tororg" "torguard" "vpnunlimited" "vyprvpn" "windscribe" "Other/Custom")
select opt in "${options[@]}"
do
    case $opt in
        "Other/Custom") read -p "Enter provider name: " VAL_PROVIDER; break ;;
        *) if [ -n "$opt" ]; then VAL_PROVIDER=$opt; break; fi ;;
    esac
done
echo -e "${GREEN}Selected: $VAL_PROVIDER${NC}"

prompt_user "SERVER_COUNTRIES" "Netherlands" "VPN Server Country"
VAL_COUNTRIES=$USER_INPUT

echo -e "\n--- VPN PROTOCOL ---"
echo "1) OpenVPN"
echo "2) WireGuard"
read -p "Select [1-2]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[2]$ ]]; then
    VAL_TYPE="wireguard"
    read -p "WireGuard Private Key: " VAL_WG_KEY
    read -p "WireGuard IPv4 Address (Optional): " VAL_WG_ADDR
    VAL_VPN_USER=""
    VAL_VPN_PASS=""
else
    VAL_TYPE="openvpn"
    read -p "Enter VPN Username: " VAL_VPN_USER
    read -p "Enter VPN Password: " VAL_VPN_PASS
    echo ""
    VAL_WG_KEY=""
    VAL_WG_ADDR=""
fi

prompt_user "WEBUI_PORT" "8091" "qBittorrent WebUI Port"
VAL_WEBUI=$USER_INPUT
prompt_user "TORRENTING_PORT" "6881" "qBittorrent Traffic Port"
VAL_TORRENT=$USER_INPUT

# --- WRITE .ENV ---
echo -e "\nWriting .env file..."
cat > "$STACK_DIR/.env" <<EOF
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

# --- CREATE DIRECTORIES ---
echo -e "\nCreating directories..."
mkdir -p "$VAL_CONFIG"/{jellyfin,prowlarr,radarr,sonarr,qbittorrent}
mkdir -p "$VAL_MEDIA"/{torrents/.incomplete,media/movies,media/tv}

# --- START STACK (STAGED) ---
echo "========================================"
echo "   SETUP COMPLETE"
echo "========================================"
read -p "Start the stack now? (y/n): " -n 1 -r
echo
if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
    cd "$STACK_DIR" || exit 1
    
    # 1. START VPN FIRST
    echo -e "\n${BLUE}Phase 1: Starting VPN (Gluetun)...${NC}"
    docker compose up -d gluetun

    # 2. START THE REST
    echo -e "\n${BLUE}Phase 2: Starting Services...${NC}"
    docker compose up -d
    
    HOST_IP=$(hostname -I | awk '{print $1}')
    echo "========================================"
    echo -e "${GREEN}Stack started successfully!${NC}"
    echo "Access your services at http://$HOST_IP:PORT"
    echo "========================================"
else
    echo "Run 'docker compose up -d' to start."
fi