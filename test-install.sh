#!/bin/bash

echo "========================================"
echo "   DIAGNOSTIC: SMART VARIABLE DETECTION"
echo "========================================"

# 1. Detect User ID (PUID)
DETECTED_PUID=$(id -u)
echo "User ID (PUID):      $DETECTED_PUID"

# 2. Detect Group ID (PGID)
DETECTED_PGID=$(id -g)
echo "Group ID (PGID):     $DETECTED_PGID"

# 3. Detect Timezone (TZ)
# Tries timedatectl first, falls back to America/New_York if not found
DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/New_York (Fallback)")
echo "Timezone (TZ):       $DETECTED_TZ"

# 4. Detect Home Directory
DETECTED_HOME=$HOME
echo "Home Directory:      $DETECTED_HOME"

# 5. Detect Host IP
DETECTED_IP=$(hostname -I | awk '{print $1}')
echo "Host IP Address:     $DETECTED_IP"

# 6. Detect Local Subnet
# Logic: List routes -> find line matching host IP -> print first column
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)

DETECTED_SUBNET=$(ip route | grep "dev $DEFAULT_IFACE" | grep -v "^default" | awk '{print $1}' | head -n 1)

# Fallback check
if [ -z "$DETECTED_SUBNET" ]; then
    # Detection failed - Show the WARNING
    DEFAULT_SUBNET="192.168.1.0/24"
    echo -e "\n--- LOCAL_SUBNET ---"
    echo -e "${RED}⚠️  WARNING: Could not detect your local subnet automatically.${NC}"
    echo "This setting is CRITICAL. It allows you to access the WebUI while the VPN is running."
    echo "If you set this wrong, you will be locked out of the web interfaces."
    echo ""
    echo "Common defaults: 192.168.1.0/24, 192.168.0.0/24, 10.0.0.0/24"
    echo "Please check your router or network settings."
    echo -e "Defaulting to guess: ${YELLOW}$DEFAULT_SUBNET${NC}"
    
    read -p "Enter your Subnet (CIDR format): " input
    if [ -z "$input" ]; then
        VAL_SUBNET="$DEFAULT_SUBNET"
    else
        VAL_SUBNET="$input"
    fi
else
    # Detection succeeded - Show the standard prompt
    echo -e "${GREEN}Success! Detected: $DETECTED_SUBNET${NC}"
    prompt_user "LOCAL_SUBNET" "$DETECTED_SUBNET" "Your LAN Subnet. Required for WebUI access."
    VAL_SUBNET=$USER_INPUT
fi
echo "Local Subnet:        $DETECTED_SUBNET"

echo "========================================"
echo "   TEST COMPLETE"
echo "========================================"