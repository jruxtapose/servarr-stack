#!/bin/bash

# --- COLOR DEFINITIONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 2. PRE-FLIGHT CHECK: IS IT INSTALLED?
ENV_FILE="$STACK_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}ERROR: Stack not found (no .env file).${NC}"
    echo "Please install the stack first."
    exit 1
fi

echo "========================================"
echo -e "${BLUE}   SERVARR STACK UPDATER${NC}"
echo "========================================"
echo "Checking for updates..."
echo "This may take a moment as we query remote registries."
echo ""

# Get list of services defined in compose file
# We use docker compose config to parse valid services
pushd "$STACK_DIR" > /dev/null
SERVICES=$(docker compose config --services)

if [ -z "$SERVICES" ]; then
    echo -e "${RED}Error: Could not read services from docker-compose.yml${NC}"
    exit 1
fi

# Initialize update counter
UPDATES_FOUND=0

# Loop through each service
for SERVICE in $SERVICES; do
    # Get the image name currently used by the service
    IMAGE=$(docker compose config | grep "image:.*$SERVICE" -B 5 | grep "image:" | awk '{print $2}' | head -n 1)
    
    # If we couldn't grep the image (sometimes format varies), try a direct inspect on the running container
    if [ -z "$IMAGE" ]; then
        IMAGE=$(docker inspect --format='{{.Config.Image}}' $(docker compose ps -q $SERVICE) 2>/dev/null)
    fi

    if [ -z "$IMAGE" ]; then
        echo -e "${YELLOW}Skipping $SERVICE (Could not detect image name)${NC}"
        continue
    fi

    printf "Checking %-15s ($IMAGE)... " "$SERVICE"

    # Pull the latest manifest info from remote (without downloading image)
    # We grep for the digest
    REMOTE_DIGEST=$(docker manifest inspect "$IMAGE" -v 2>/dev/null | grep '"digest":' | head -n 1 | awk -F '"' '{print $4}')
    
    # Get local digest
    LOCAL_DIGEST=$(docker inspect --format='{{.RepoDigests}}' "$IMAGE" 2>/dev/null | awk -F '@' '{print $2}' | awk -F ']' '{print $1}')

    if [ -z "$REMOTE_DIGEST" ]; then
        echo -e "${RED}Failed to query registry.${NC}"
        continue
    fi

    if [ "$REMOTE_DIGEST" != "$LOCAL_DIGEST" ]; then
        echo -e "${GREEN}UPDATE AVAILABLE!${NC}"
        UPDATES_FOUND=1
        
        echo -e "\n${YELLOW}⚠️  WARNING FOR $SERVICE:${NC}"
        echo "   Updating containers can sometimes break configuration or database compatibility."
        echo "   Ensure you have backups of your 'config' folder before proceeding."
        
        read -p "   Do you want to update $SERVICE? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "   ${BLUE}Updating $SERVICE...${NC}"
            
            # Pull the new image
            docker compose pull "$SERVICE"
            
            # Recreate the container
            docker compose up -d --no-deps "$SERVICE"
            
            # Prune the old image to save space
            docker image prune -f > /dev/null
            
            echo -e "   ${GREEN}✅ $SERVICE updated successfully.${NC}\n"
        else
            echo -e "   ${YELLOW}Skipping update for $SERVICE.${NC}\n"
        fi
    else
        echo -e "${GREEN}Up to date.${NC}"
    fi
done

popd > /dev/null

echo "========================================"
if [ $UPDATES_FOUND -eq 0 ]; then
    echo -e "${GREEN}   ALL SERVICES ARE UP TO DATE${NC}"
else
    echo -e "${BLUE}   UPDATE PROCESS COMPLETE${NC}"
fi
echo "========================================"