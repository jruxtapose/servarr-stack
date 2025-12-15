#!/bin/bash

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- 1. SMART DIRECTORY DETECTION ---
if [ -f "docker-compose.yml" ]; then
    STACK_DIR="."
    DISPLAY_DIR="Current Directory"
elif [ -f "servarr/docker-compose.yml" ]; then
    STACK_DIR="servarr"
    DISPLAY_DIR="./servarr"
else
    echo -e "${RED}ERROR: Could not find 'docker-compose.yml'.${NC}"
    echo "Please ensure this script is in the 'servarr-stack' folder and the compose file is inside 'servarr/'."
    exit 1
fi

# --- 2. PRE-FLIGHT CHECK: ALREADY INSTALLED? ---
if [ -f "$STACK_DIR/.env" ]; then
    echo "========================================"
    echo -e "${RED}   STACK ALREADY INSTALLED${NC}"
    echo "========================================"
    echo "An '.env' file was found in $DISPLAY_DIR."
    echo "This indicates the stack is already configured."
    echo ""
    echo "If you want to reinstall, please run './uninstall.sh' first."
    exit 1
fi

echo "========================================"
echo "   SERVARR VPN STACK INSTALLER"
echo "========================================"
echo -e "Target Directory: ${GREEN}$DISPLAY_DIR${NC}"

# --- HELPER FUNCTION FOR PROMPTS ---
prompt_user() {
    local var_name=$1
    local default_val=$2
    local desc=$3
    
    echo -e "\n--- $var_name ---"
    echo -e "$desc"
    echo -e "Default: $default_val"
    read -p "Enter value (or press ENTER to use default): " input
    
    if [ -z "$input" ]; then
        USER_INPUT="$default_val"
    else
        USER_INPUT="$input"
    fi
}

# 0. Safety Check: Ensure script is NOT run as root
if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}Please do not run this script as root (sudo).${NC}"
  echo "Run it as your normal user. The script will ask for sudo when needed."
  exit 1
fi

# 3. Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not currently installed."
    echo "Default: No"
    read -p "Would you like to install Docker automatically? (y/n): " -n 1 -r
    echo 
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Downloading and running official Docker install script..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo usermod -aG docker $USER
        echo -e "${GREEN}Docker installed. You may need to log out/in for group changes.${NC}"
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

# --- CALCULATE SMART DEFAULTS ---
DEFAULT_PUID=$(id -u)
DEFAULT_PGID=$(id -g)
DEFAULT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/New_York")
DEFAULT_HOME=$HOME

# Detect Local Subnet
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
DETECTED_SUBNET=$(ip route | grep "dev $DEFAULT_IFACE" | grep -v "^default" | awk '{print $1}' | head -n 1)

if [ -z "$DETECTED_SUBNET" ]; then
    DETECTED_SUBNET="192.168.1.0/24"
    echo -e "${RED}WARNING: Could not automatically detect your local subnet.${NC}"
    echo "Defaulting to 192.168.1.0/24. If this is incorrect, your WebUIs will be inaccessible."
fi

# --- GATHER INPUTS ---

# 1. PUID/PGID
prompt_user "PUID" "$DEFAULT_PUID" "User ID to run containers as."
VAL_PUID=$USER_INPUT

prompt_user "PGID" "$DEFAULT_PGID" "Group ID to run containers as."
VAL_PGID=$USER_INPUT

# 2. Timezone
prompt_user "TZ" "$DEFAULT_TZ" "System Timezone"
VAL_TZ=$USER_INPUT

# 3. Directories
prompt_user "CONFIG_ROOT" "./config" "Where to store app config files (Relative to stack)."
VAL_CONFIG=$USER_INPUT

prompt_user "MEDIA_ROOT" "$DEFAULT_HOME" "Base folder for all media and downloads."
VAL_MEDIA=$USER_INPUT

# 4. Network
prompt_user "LOCAL_SUBNET" "$DETECTED_SUBNET" "Your LAN Subnet. REQUIRED for WebUI access."
VAL_SUBNET=$USER_INPUT

# 5. VPN Settings (Provider Selection)
echo -e "\n--- VPN PROVIDER ---"
echo "Select your VPN Service Provider:"
# Common providers listed here. 'custom' allows manual entry for others.
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
            if [ -n "$opt" ]; then
                VAL_PROVIDER=$opt
                break
            else
                echo "Invalid option. Try again."a 
            fi
            ;;
    esac
done
echo -e "${GREEN}Selected Provider: $VAL_PROVIDER${NC}"


prompt_user "SERVER_COUNTRIES" "Netherlands" "VPN Server Country"
VAL_COUNTRIES=$USER_INPUT

echo -e "\n--- VPN PROTOCOL ---"
echo "Select your VPN Protocol:"
echo "1) OpenVPN (Standard, easier setup)"
echo "2) WireGuard (Faster, requires Keys)"
read -p "Select [1-2]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[2]$ ]]; then
    VAL_TYPE="wireguard"
    echo -e "${GREEN}Selected: WireGuard${NC}"
    echo "Please enter your WireGuard details (found in your provider's config generator)."
    
    read -p "WireGuard Private Key: " VAL_WG_KEY
    read -p "WireGuard IPv4 Address (Optional, press Enter if unsure): " VAL_WG_ADDR
    
    # Clear OpenVPN vars to avoid confusion
    VAL_VPN_USER=""
    VAL_VPN_PASS=""
else
    VAL_TYPE="openvpn"
    echo -e "${GREEN}Selected: OpenVPN${NC}"
    echo "Note: Many providers use specific Service Credentials, not your website login."
    read -p "Enter VPN Username: " VAL_VPN_USER
    read -s -p "Enter VPN Password: " VAL_VPN_PASS
    echo ""
    
    # Clear WireGuard vars
    VAL_WG_KEY=""
    VAL_WG_ADDR=""
fi


# 6. Ports
prompt_user "WEBUI_PORT" "8091" "qBittorrent WebUI Port"
VAL_WEBUI=$USER_INPUT

prompt_user "TORRENTING_PORT" "6881" "qBittorrent Traffic Port"
VAL_TORRENT=$USER_INPUT


# --- WRITE .ENV FILE ---
echo -e "\nWriting .env file to $DISPLAY_DIR/.env ..."

cat > "$STACK_DIR/.env" <<EOF
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

# OpenVPN Credentials
OPENVPN_USER=$VAL_VPN_USER
OPENVPN_PASSWORD=$VAL_VPN_PASS

# WireGuard Credentials
WIREGUARD_PRIVATE_KEY=$VAL_WG_KEY
WIREGUARD_ADDRESSES=$VAL_WG_ADDR

WEBUI_PORT=$VAL_WEBUI
TORRENTING_PORT=$VAL_TORRENT
EOF

echo -e "${GREEN}.env file created successfully.${NC}"

# --- CREATE DIRECTORIES ---
echo -e "\n--- CREATE DIRECTORIES ---"
echo "Default: Yes"
read -p "Create config directories at $STACK_DIR/$VAL_CONFIG? (y/n): " -n 1 -r
echo
if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
    FULL_CONFIG_PATH="$STACK_DIR/$VAL_CONFIG"
    
    mkdir -p "$FULL_CONFIG_PATH/jellyfin" \
             "$FULL_CONFIG_PATH/prowlarr" \
             "$FULL_CONFIG_PATH/radarr" \
             "$FULL_CONFIG_PATH/sonarr" \
             "$FULL_CONFIG_PATH/qbittorrent"
    echo -e "${GREEN}Directories created at $FULL_CONFIG_PATH${NC}"
else
    echo "Skipping directory creation."
fi

# --- START STACK ---
echo "========================================"
echo "   SETUP COMPLETE"
echo "========================================"
echo "Default: Yes"
read -p "Would you like to start the stack now? (y/n): " -n 1 -r
echo
if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting Docker containers..."
    
    cd "$STACK_DIR" || exit 1
    
    docker compose up -d
    if [ $? -eq 0 ]; then
        HOST_IP=$(hostname -I | awk '{print $1}')
        echo "========================================"
        echo -e "${GREEN}Stack started successfully!${NC}"
        echo "   Access your services here:"
        echo "========================================"
        echo " - Jellyfin:    http://$HOST_IP:8096"
        echo " - Sonarr:      http://$HOST_IP:8989"
        echo " - Radarr:      http://$HOST_IP:7878"
        echo " - Prowlarr:    http://$HOST_IP:9696"
        echo " - qBittorrent: http://$HOST_IP:$VAL_WEBUI"
        echo " - Flaresolverr:http://$HOST_IP:8191"
        echo "========================================"
    else
        echo -e "${RED}Failed to start stack. Check permissions or docker logs.${NC}"
    fi
else
    echo "You can start the stack later by running: cd $DISPLAY_DIR && docker compose up -d"
fi