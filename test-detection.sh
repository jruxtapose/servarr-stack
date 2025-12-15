#!/bin/bash

echo "========================================"
echo "   DIAGNOSTIC: SMART VARIABLE DETECTION"
echo "========================================"

# --- ROBUST SUBNET DETECTION ---
# 1. Find the interface used for the default route (internet access)
#    (e.g., eth0, enp3s0, wlan0)
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)

# 2. Find the subnet associated with that interface
#    excludes the 'default' line itself to find the actual subnet range
DETECTED_SUBNET=$(ip route | grep "dev $DEFAULT_IFACE" | grep -v "^default" | awk '{print $1}' | head -n 1)

# Fallback
if [ -z "$DETECTED_SUBNET" ]; then
    DETECTED_SUBNET="Detection Failed (Defaulting to 192.168.1.0/24)"
fi

echo "Detected Interface:  $DEFAULT_IFACE"
echo "Detected Subnet:     $DETECTED_SUBNET"
echo "========================================"