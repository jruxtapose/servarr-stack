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

# Resolve absolute paths to compare strictly
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

    # Check if the target already exists (collision check)
    if [ -d "$REQUIRED_DIR" ]; then
        echo -e "${RED}Target folder '$REQUIRED_DIR' already exists!${NC}"
        echo "We cannot move this folder automatically because it would overwrite existing files."
        echo "Please fix your directory structure manually."
        exit 1
    fi

    echo "I can move this entire folder to the correct location for you."
    read -p "Move folder and exit? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Moving files..."
        
        # Move the current directory to the required path
        # We assume the user is sitting INSIDE the folder they want to move
        # So we move the parent directory logic or just the current contents?
        # Safest is to move the directory itself.
        
        # We need to jump out one level to move "this" folder
        PARENT_DIR=$(dirname "$ABS_CURRENT")
        FOLDER_NAME=$(basename "$ABS_CURRENT")
        
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
        echo "You must move this folder to $REQUIRED_DIR before running."
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
    echo "Please ensure this script is in the 'servarr-stack' folder and the compose file is inside 'servarr/'."
    exit 1
fi

# --- 2. PRE-FLIGHT CHECK: ALREADY INSTALLED? ---
if [ -f "$STACK_DIR/.env" ]; then
    echo "========================================"
    echo -e "${RED}   STACK ALREADY INSTALLED${NC}"
    echo "========================================"
    echo "An '.env' file was found in $DISPLAY_DIR."
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
    echo -e "Default: ${YELLOW}$default_val${NC}"
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
    read -p "Install Docker automatically? (y/n): " -n 1 -r
    echo 
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo usermod -aG docker $USER
        echo -e "${GREEN}Docker installed. Log out and back in for changes to apply.${NC}"
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

# 1. PUID/PGID
prompt_user "PUID" "$DEFAULT_PUID" "User ID to run containers as."
VAL_PUID=$USER_INPUT

prompt_user "PGID" "$DEFAULT_PGID" "Group ID to run containers as."
VAL_PGID=$USER_INPUT

# 2. Timezone
prompt_user "TZ" "$DEFAULT_TZ" "System Timezone"
VAL_TZ=$USER_INPUT

# 3. Network
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
DETECTED_SUBNET=$(ip route | grep "dev $DEFAULT_IFACE" | grep -v "^default" | awk '{print $1}' | head -n 1)

if [ -z "$DETECTED_SUBNET" ]; then
    DEFAULT_SUBNET="192.168.1.0/24"
    echo -e "\n--- LOCAL_SUBNET ---"
    echo -e "${RED}⚠️  WARNING: Could not detect your local subnet.${NC}"
    echo -e "Defaulting to guess: ${YELLOW}$DEFAULT_SUBNET${NC}"
    read -p "Enter your Subnet (CIDR format): " input
    if [ -z "$input" ]; then VAL_SUBNET="$DEFAULT_SUBNET"; else VAL_SUBNET="$input"; fi
else
    prompt_user "LOCAL_SUBNET" "$DETECTED_SUBNET" "Your LAN Subnet. Required for WebUI access."
    VAL_SUBNET=$USER_INPUT
fi

# 4. VPN Settings
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
            if [ -n "$opt" ]; then
                VAL_PROVIDER=$opt
                break
            else
                echo "Invalid option. Try again."
            fi
            ;;
    esac
done
echo -e "${GREEN}Selected Provider: $VAL_PROVIDER${NC}"

prompt_user "SERVER_COUNTRIES" "Netherlands" "VPN Server Country"
VAL_COUNTRIES=$USER_INPUT

echo -e "\n--- VPN PROTOCOL ---"
echo "Select your VPN Protocol:"
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

# 5. Ports
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
OPENVPN_USER=$VAL_VPN_USER
OPENVPN_PASSWORD=$VAL_VPN_PASS
WIREGUARD_PRIVATE_KEY=$VAL_WG_KEY
WIREGUARD_ADDRESSES=$VAL_WG_ADDR
WEBUI_PORT=$VAL_WEBUI
TORRENTING_PORT=$VAL_TORRENT
EOF
echo -e "${GREEN}.env file created successfully.${NC}"

# --- CREATE DIRECTORIES ---
echo -e "\n--- CREATE DIRECTORIES ---"
echo "Creating enforced config and data directories..."

mkdir -p "$VAL_CONFIG/jellyfin" \
         "$VAL_CONFIG/prowlarr" \
         "$VAL_CONFIG/radarr" \
         "$VAL_CONFIG/sonarr" \
         "$VAL_CONFIG/qbittorrent"

mkdir -p "$VAL_MEDIA/torrents" \
         "$VAL_MEDIA/torrents/.incomplete" \
         "$VAL_MEDIA/media/movies" \
         "$VAL_MEDIA/media/tv"

echo -e "${GREEN}Directories created at:$NC"
echo " - $VAL_CONFIG"
echo " - $VAL_MEDIA"

# --- START STACK ---
echo "========================================"
echo "   SETUP COMPLETE"
echo "========================================"
read -p "Start the stack now? (y/n): " -n 1 -r
echo
if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting Docker containers..."
    cd "$STACK_DIR" || exit 1
    docker compose up -d
    HOST_IP=$(hostname -I | awk '{print $1}')
    echo "========================================"
    echo -e "${GREEN}Stack started successfully!${NC}"
    echo "Access your services at http://$HOST_IP:PORT"
    echo "========================================"
else
    echo "Run 'docker compose up -d' in the $DISPLAY_DIR folder to start."
fi