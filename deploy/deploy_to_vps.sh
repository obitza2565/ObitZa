#!/bin/bash
# =============================================================================
# OBZ Virtual Mining - One-Click Deploy to Hetzner VPS (Bash version)
# =============================================================================
# Usage: ./deploy_to_vps.sh --ip 123.123.123.123 --domain obzexchange.com
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
VPS_IP=""
SSH_USER="root"
DOMAIN="obzexchange.com"
API_SUBDOMAIN="api.obzexchange.com"
SKIP_SSL=false
SKIP_BASIC_AUTH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip)
            VPS_IP="$2"
            shift 2
            ;;
        --user)
            SSH_USER="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --api-domain)
            API_SUBDOMAIN="$2"
            shift 2
            ;;
        --skip-ssl)
            SKIP_SSL=true
            shift
            ;;
        --skip-basic-auth)
            SKIP_BASIC_AUTH=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$VPS_IP" ]; then
    echo -e "${RED}Error: VPS IP is required${NC}"
    echo "Usage: $0 --ip 123.123.123.123 [--domain obzexchange.com]"
    exit 1
fi

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     OBZ Virtual Mining - VPS Deployment Script              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Step 1: Pre-flight checks
# =============================================================================
echo -e "${YELLOW}[1/8] Running pre-flight checks...${NC}"

if [ ! -f "virtual-mining/.env" ]; then
    echo -e "${RED}ERROR: virtual-mining/.env not found!${NC}"
    echo "Please copy .env.example to .env and fill in your secrets first."
    exit 1
fi

if [ ! -d "virtual-mining/dist" ]; then
    echo -e "${YELLOW}Building TypeScript...${NC}"
    cd virtual-mining
    npm install
    npm run build
    cd ..
fi

echo -e "  ${GREEN}✓ All checks passed${NC}"

# =============================================================================
# Step 2: Test SSH connection
# =============================================================================
echo -e "${YELLOW}[2/8] Testing SSH connection to $VPS_IP...${NC}"

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_USER@$VPS_IP" "echo 'SSH OK'" 2>/dev/null; then
    echo -e "${RED}ERROR: Cannot connect to VPS via SSH!${NC}"
    echo "Please ensure:"
    echo "  1. VPS IP is correct: $VPS_IP"
    echo "  2. SSH key is added: ssh-copy-id $SSH_USER@$VPS_IP"
    echo "  3. Or use password: ssh $SSH_USER@$VPS_IP"
    exit 1
fi
echo -e "  ${GREEN}✓ SSH connection successful${NC}"

# =============================================================================
# Step 3: Create remote directories
# =============================================================================
echo -e "${YELLOW}[3/8] Creating remote directories...${NC}"

ssh "$SSH_USER@$VPS_IP" << 'EOF'
mkdir -p /opt/obz/virtual-mining
mkdir -p /opt/obz/exchange
mkdir -p /var/log/obz
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
EOF

echo -e "  ${GREEN}✓ Directories created${NC}"

# =============================================================================
# Step 4: Upload files
# =============================================================================
echo -e "${YELLOW}[4/8] Uploading files to VPS...${NC}"

# Upload virtual-mining
echo "  Uploading virtual-mining service..."
rsync -avz --progress \
    --exclude 'node_modules' \
    --exclude '.env' \
    --exclude 'logs' \
    virtual-mining/ "$SSH_USER@$VPS_IP:/opt/obz/virtual-mining/"

# Upload .env separately (secure)
scp virtual-mining/.env "$SSH_USER@$VPS_IP:/opt/obz/virtual-mining/"

# Upload exchange
echo "  Uploading exchange frontend..."
rsync -avz --progress \
    exchange/ "$SSH_USER@$VPS_IP:/opt/obz/exchange/"

echo -e "  ${GREEN}✓ Files uploaded${NC}"

# =============================================================================
# Step 5: Install Node.js and dependencies
# =============================================================================
echo -e "${YELLOW}[5/8] Setting up Node.js on VPS...${NC}"

ssh "$SSH_USER@$VPS_IP" << 'EOF'
# Install Node.js 20 if not present
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Install dependencies
cd /opt/obz/virtual-mining
npm install --production

# Create logs directory
mkdir -p logs
EOF

echo -e "  ${GREEN}✓ Node.js setup complete${NC}"

# =============================================================================
# Step 6: Configure systemd service
# =============================================================================
echo -e "${YELLOW}[6/8] Configuring systemd service...${NC}"

ssh "$SSH_USER@$VPS_IP" << 'EOF'
cat > /etc/systemd/system/obz-vmining.service << 'SERVICEEOF'
[Unit]
Description=OBZ Virtual Mining Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/obz/virtual-mining
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

# Logging
StandardOutput=append:/var/log/obz/vmining.log
StandardError=append:/var/log/obz/vmining.error.log

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable obz-vmining
systemctl restart obz-vmining
sleep 2
systemctl status obz-vmining --no-pager
EOF

echo -e "  ${GREEN}✓ Service configured and started${NC}"

# =============================================================================
# Step 7: Configure Nginx
# =============================================================================
echo -e "${YELLOW}[7/8] Configuring Nginx...${NC}"

# Main site config
ssh "$SSH_USER@$VPS_IP" << EOF
cat > /etc/nginx/sites-available/obz-main << 'NGINXEOF'
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    root /opt/obz/exchange;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:4100;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
    }
}
NGINXEOF

cat > /etc/nginx/sites-available/obz-api << 'NGINXEOF'
server {
    listen 80;
    server_name $API_SUBDOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:4100;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXEOF

# Enable sites
ln -sf /etc/nginx/sites-available/obz-main /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/obz-api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload
nginx -t
systemctl reload nginx
EOF

echo -e "  ${GREEN}✓ Nginx configured${NC}"

# =============================================================================
# Step 8: Setup Basic Auth and SSL
# =============================================================================
echo -e "${YELLOW}[8/8] Finalizing security...${NC}"

if [ "$SKIP_BASIC_AUTH" = false ]; then
    echo "  Setting up Basic Auth (username: admin)..."
    ssh "$SSH_USER@$VPS_IP" "htpasswd -cb /etc/nginx/.htpasswd admin '$(openssl rand -base64 12)'"
    echo "  ${YELLOW}Note: Basic Auth password was auto-generated. Change it with:${NC}"
    echo "    ssh $SSH_USER@$VPS_IP 'htpasswd /etc/nginx/.htpasswd admin'"
fi

if [ "$SKIP_SSL" = false ]; then
    echo "  Setting up SSL with Let's Encrypt..."
    echo "  Note: This requires DNS to be pointing to this VPS!"
    read -p "  Continue with SSL setup? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh "$SSH_USER@$VPS_IP" << EOF
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d $DOMAIN -d www.$DOMAIN -d $API_SUBDOMAIN --non-interactive --agree-tos --register-unsafely-without-email || echo "SSL setup failed - DNS may not be ready"
EOF
    fi
fi

echo -e "  ${GREEN}✓ Security configured${NC}"

# =============================================================================
# Deployment Complete
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           DEPLOYMENT COMPLETE!                               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Your OBZ Virtual Mining is now live at:${NC}"
echo -e "  🌐 Main Site:  http://$DOMAIN"
echo -e "  ⛏️  Mining:     http://$DOMAIN/mining.html"
echo -e "  🛡️  Admin:      http://$DOMAIN/admin-withdrawals.html"
echo -e "  🔧 API:        http://$API_SUBDOMAIN"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Fund your Hot Wallet: 0x41a0096ef2E784d574156Ddec32853B666C6dbE1"
echo "  2. Monitor logs: ssh $SSH_USER@$VPS_IP 'journalctl -u obz-vmining -f'"
echo "  3. Check status: ssh $SSH_USER@$VPS_IP 'systemctl status obz-vmining'"
echo ""
echo -e "${YELLOW}Security reminders:${NC}"
echo "  - Change ADMIN_API_KEY in /opt/obz/virtual-mining/.env"
echo "  - Setup firewall: ufw allow 80,443/tcp && ufw enable"
echo "  - Enable automatic security updates"
echo ""
