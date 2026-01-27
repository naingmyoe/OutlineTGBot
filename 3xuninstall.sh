#!/bin/bash

# 3xbot Uninstaller
# This script will remove the bot files and stop the process.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=====================================================${NC}"
echo -e "${RED}       3xbot Uninstaller (Clean Wipe)                ${NC}"
echo -e "${RED}=====================================================${NC}"

# Check Root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}[Error] Please run as root (sudo -i)${NC}"
  exit 1
fi

echo -e "${YELLOW}[INFO] 1/3 Stopping PM2 Process...${NC}"

# Check if PM2 is installed and remove the bot
if command -v pm2 &> /dev/null; then
    pm2 stop 3xbot 2>/dev/null
    pm2 delete 3xbot 2>/dev/null
    pm2 save --force 2>/dev/null
    echo -e "${GREEN}✅ Bot process stopped and removed from PM2.${NC}"
else
    echo -e "${YELLOW}⚠️ PM2 not found. Skipping process stop.${NC}"
fi

echo -e "${YELLOW}[INFO] 2/3 Removing Files...${NC}"

# Define Directory
DIR="/root/3xbot"

if [ -d "$DIR" ]; then
    rm -rf "$DIR"
    echo -e "${GREEN}✅ Deleted directory: $DIR${NC}"
else
    echo -e "${YELLOW}⚠️ Directory not found (Already deleted?).${NC}"
fi

echo -e "${YELLOW}[INFO] 3/3 Cleaning up...${NC}"
echo -e "${GREEN}✅ Uninstall Complete! The bot is gone.${NC}"
echo -e "${RED}=====================================================${NC}"
