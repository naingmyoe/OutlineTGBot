#!/bin/bash

# Color Codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing Nginx for Web Panel + Bot ===${NC}"

# 1. Update Nginx Config to serve both Web & API
echo -e "${YELLOW}Configuring Nginx to show Web Panel...${NC}"
cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name _;
    
    # 1. Serve the Web Panel (Frontend)
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    # 2. Proxy API requests to Bot (Backend)
    location /api/ {
        proxy_pass http://localhost:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# 2. Restart Nginx to apply changes
echo -e "${YELLOW}Restarting Nginx...${NC}"
systemctl reload nginx
systemctl restart nginx

# 3. Restart Bot to ensure API is ready
echo -e "${YELLOW}Restarting Bot Process...${NC}"
pm2 restart vpn-shop

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN} FIX COMPLETE! Refresh your browser now. ${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "Panel URL: http://$(curl -s ifconfig.me)"
