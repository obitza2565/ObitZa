# =============================================================================
# OBZ Virtual Mining - One-Click Deploy to Hetzner VPS
# =============================================================================
# Usage: .\deploy_to_vps.ps1 -VpsIp "123.123.123.123" -SshUser "root" -Domain "obzexchange.com"
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$VpsIp,
    
    [Parameter(Mandatory=$false)]
    [string]$SshUser = "root",
    
    [Parameter(Mandatory=$false)]
    [string]$Domain = "obzexchange.com",
    
    [Parameter(Mandatory=$false)]
    [string]$ApiSubdomain = "api.obzexchange.com",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipSsl = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBasicAuth = $false
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     OBZ Virtual Mining - VPS Deployment Script              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Step 1: Pre-flight checks
# =============================================================================
Write-Host "[1/8] Running pre-flight checks..." -ForegroundColor Yellow

# Check if .env exists
$envPath = Join-Path $projectRoot "virtual-mining\.env"
if (-not (Test-Path $envPath)) {
    Write-Host "ERROR: virtual-mining\.env not found!" -ForegroundColor Red
    Write-Host "Please copy .env.example to .env and fill in your secrets first." -ForegroundColor Red
    exit 1
}

# Check if dist exists
$distPath = Join-Path $projectRoot "virtual-mining\dist"
if (-not (Test-Path $distPath)) {
    Write-Host "Building TypeScript..." -ForegroundColor Yellow
    Set-Location (Join-Path $projectRoot "virtual-mining")
    node node_modules\typescript\bin\tsc -p tsconfig.json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: TypeScript build failed!" -ForegroundColor Red
        exit 1
    }
    Set-Location $projectRoot
}

# Check required files
$requiredFiles = @(
    "virtual-mining\package.json",
    "virtual-mining\dist\index.js",
    "virtual-mining\.env",
    "exchange\admin-withdrawals.html",
    "exchange\mining.html",
    "exchange\index.html"
)

foreach ($file in $requiredFiles) {
    $fullPath = Join-Path $projectRoot $file
    if (-not (Test-Path $fullPath)) {
        Write-Host "ERROR: Required file missing: $file" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  ✓ All checks passed" -ForegroundColor Green

# =============================================================================
# Step 2: Test SSH connection
# =============================================================================
Write-Host "[2/8] Testing SSH connection to $VpsIp..." -ForegroundColor Yellow

$sshTest = ssh -o ConnectTimeout=10 -o BatchMode=yes "$SshUser@$VpsIp" "echo 'SSH OK'" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Cannot connect to VPS via SSH!" -ForegroundColor Red
    Write-Host "Please ensure:" -ForegroundColor Red
    Write-Host "  1. VPS IP is correct: $VpsIp" -ForegroundColor Red
    Write-Host "  2. SSH key is added: ssh-copy-id $SshUser@$VpsIp" -ForegroundColor Red
    Write-Host "  3. Or use password: ssh $SshUser@$VpsIp" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ SSH connection successful" -ForegroundColor Green

# =============================================================================
# Step 3: Create remote directories
# =============================================================================
Write-Host "[3/8] Creating remote directories..." -ForegroundColor Yellow

ssh "$SshUser@$VpsIp" @"
mkdir -p /opt/obz/virtual-mining
mkdir -p /opt/obz/exchange
mkdir -p /var/log/obz
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
"@

Write-Host "  ✓ Directories created" -ForegroundColor Green

# =============================================================================
# Step 4: Upload files
# =============================================================================
Write-Host "[4/8] Uploading files to VPS..." -ForegroundColor Yellow

# Create tarball of virtual-mining
$tarPath = Join-Path $env:TEMP "obz-vmining.tar.gz"
Write-Host "  Creating tarball..." -ForegroundColor Gray

# Use 7-Zip if available, otherwise use tar
if (Get-Command 7z -ErrorAction SilentlyContinue) {
    Set-Location (Join-Path $projectRoot "virtual-mining")
    7z a -ttar -so . | 7z a -si $tarPath -tgzip
    Set-Location $projectRoot
} else {
    # Fallback to scp individual files
    Write-Host "  Using SCP (slower)..." -ForegroundColor Gray
    scp -r "$projectRoot\virtual-mining\dist" "${SshUser}@${VpsIp}:/opt/obz/virtual-mining/"
    scp -r "$projectRoot\virtual-mining\node_modules" "${SshUser}@${VpsIp}:/opt/obz/virtual-mining/"
    scp "$projectRoot\virtual-mining\package.json" "${SshUser}@${VpsIp}:/opt/obz/virtual-mining/"
    scp "$projectRoot\virtual-mining\.env" "${SshUser}@${VpsIp}:/opt/obz/virtual-mining/"
}

# Upload exchange files
Write-Host "  Uploading exchange frontend..." -ForegroundColor Gray
scp "$projectRoot\exchange\*.html" "${SshUser}@${VpsIp}:/opt/obz/exchange/"
scp "$projectRoot\exchange\app-config.js" "${SshUser}@${VpsIp}:/opt/obz/exchange/" 2>$null

Write-Host "  ✓ Files uploaded" -ForegroundColor Green

# =============================================================================
# Step 5: Install Node.js and dependencies
# =============================================================================
Write-Host "[5/8] Setting up Node.js on VPS..." -ForegroundColor Yellow

ssh "$SshUser@$VpsIp" @"
# Install Node.js 20 if not present
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Install dependencies
cd /opt/obz/virtual-mining
npm install --production

# Build if needed
if [ ! -d "dist" ]; then
    npm install typescript
    npx tsc -p tsconfig.json
fi

# Create logs directory
mkdir -p logs
"@

Write-Host "  ✓ Node.js setup complete" -ForegroundColor Green

# =============================================================================
# Step 6: Configure systemd service
# =============================================================================
Write-Host "[6/8] Configuring systemd service..." -ForegroundColor Yellow

$serviceContent = @"
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
"@

$serviceContent | ssh "$SshUser@$VpsIp" "cat > /etc/systemd/system/obz-vmining.service"

ssh "$SshUser@$VpsIp" @"
systemctl daemon-reload
systemctl enable obz-vmining
systemctl restart obz-vmining
sleep 2
systemctl status obz-vmining --no-pager
"@

Write-Host "  ✓ Service configured and started" -ForegroundColor Green

# =============================================================================
# Step 7: Configure Nginx
# =============================================================================
Write-Host "[7/8] Configuring Nginx..." -ForegroundColor Yellow

# Main site config
$nginxConfig = @"
server {
    listen 80;
    server_name $Domain www.$Domain;
    
    root /opt/obz/exchange;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Basic Auth (optional)
    $(if (-not $SkipBasicAuth) { @"
    auth_basic "OBZ Private Access";
    auth_basic_user_file /etc/nginx/.htpasswd;
"@ })
    
    location / {
        try_files `$uri `$uri/ =404;
    }
    
    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:4100;
        proxy_http_version 1.1;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
        proxy_cache_bypass `$http_upgrade;
        proxy_read_timeout 300s;
    }
}
"@

# API subdomain config
$nginxApiConfig = @"
server {
    listen 80;
    server_name $ApiSubdomain;
    
    location / {
        proxy_pass http://127.0.0.1:4100;
        proxy_http_version 1.1;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}
"@

$nginxConfig | ssh "$SshUser@$VpsIp" "cat > /etc/nginx/sites-available/obz-main"
$nginxApiConfig | ssh "$SshUser@$VpsIp" "cat > /etc/nginx/sites-available/obz-api"

# Enable sites
ssh "$SshUser@$VpsIp" @"
ln -sf /etc/nginx/sites-available/obz-main /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/obz-api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload
nginx -t
systemctl reload nginx
"@

Write-Host "  ✓ Nginx configured" -ForegroundColor Green

# =============================================================================
# Step 8: Setup Basic Auth and SSL
# =============================================================================
Write-Host "[8/8] Finalizing security..." -ForegroundColor Yellow

if (-not $SkipBasicAuth) {
    Write-Host "  Setting up Basic Auth (username: admin)..." -ForegroundColor Gray
    Write-Host "  Please enter password for Basic Auth:" -ForegroundColor Yellow
    ssh "$SshUser@$VpsIp" "htpasswd -c /etc/nginx/.htpasswd admin"
}

if (-not $SkipSsl) {
    Write-Host "  Setting up SSL with Let's Encrypt..." -ForegroundColor Gray
    Write-Host "  Note: This requires DNS to be pointing to this VPS!" -ForegroundColor Yellow
    
    $sslConfirm = Read-Host "  Continue with SSL setup? (y/n)"
    if ($sslConfirm -eq 'y') {
        ssh "$SshUser@$VpsIp" @"
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d $Domain -d www.$Domain -d $ApiSubdomain --non-interactive --agree-tos --register-unsafely-without-email || echo "SSL setup failed - DNS may not be ready"
"@
    }
}

Write-Host "  ✓ Security configured" -ForegroundColor Green

# =============================================================================
# Deployment Complete
# =============================================================================
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║           DEPLOYMENT COMPLETE!                               ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Your OBZ Virtual Mining is now live at:" -ForegroundColor Cyan
Write-Host "  🌐 Main Site:  http://$Domain" -ForegroundColor White
Write-Host "  ⛏️  Mining:     http://$Domain/mining.html" -ForegroundColor White
Write-Host "  🛡️  Admin:      http://$Domain/admin-withdrawals.html" -ForegroundColor White
Write-Host "  🔧 API:        http://$ApiSubdomain" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Fund your Hot Wallet: 0x41a0096ef2E784d574156Ddec32853B666C6dbE1" -ForegroundColor White
Write-Host "  2. Monitor logs: ssh $SshUser@$VpsIp 'journalctl -u obz-vmining -f'" -ForegroundColor White
Write-Host "  3. Check status: ssh $SshUser@$VpsIp 'systemctl status obz-vmining'" -ForegroundColor White
Write-Host ""
Write-Host "Security reminders:" -ForegroundColor Yellow
Write-Host "  - Change ADMIN_API_KEY in /opt/obz/virtual-mining/.env" -ForegroundColor White
Write-Host "  - Setup firewall: ufw allow 80,443/tcp && ufw enable" -ForegroundColor White
Write-Host "  - Enable automatic security updates" -ForegroundColor White
Write-Host ""
