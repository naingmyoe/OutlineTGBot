#!/bin/bash

# အရောင်များ
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

clear
echo -e "${RED}===========================================${NC}"
echo -e "${RED}      VPN SHOP BOT UNINSTALLER 🗑️        ${NC}"
echo -e "${RED}===========================================${NC}"

echo -e "${YELLOW}⚠️  WARNING: This will delete the Bot, all User Data, and Settings!${NC}"
read -p "Are you sure you want to proceed? (y/n): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${GREEN}Operation Cancelled.${NC}"
    exit 1
fi

echo -e ""
# 1. Stopping PM2 Process
echo -e "${YELLOW}🛑 Stopping Bot Process...${NC}"
pm2 stop vpn-shop > /dev/null 2>&1
pm2 delete vpn-shop > /dev/null 2>&1
pm2 save --force > /dev/null 2>&1

# 2. Removing Directory
echo -e "${YELLOW}🗑️  Deleting Project Files (/root/vpn-shop)...${NC}"
if [ -d "/root/vpn-shop" ]; then
    rm -rf /root/vpn-shop
    echo -e "${GREEN}✅ Project folder deleted.${NC}"
else
    echo -e "${RED}❌ Project folder not found (already deleted?).${NC}"
fi

# 3. Optional: Remove Global Packages (Node/PM2)
# We don't remove Node/PM2 automatically as other apps might use them.
# Uncomment the lines below if you want to remove everything completely.
# npm uninstall -g pm2
# apt remove -y nodejs

echo -e ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}   ✅ UNINSTALLATION COMPLETE!   ${NC}"
echo -e "${GREEN}===========================================${NC}"
