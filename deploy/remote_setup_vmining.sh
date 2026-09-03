#!/bin/bash
# =============================================================================
# OBZ Virtual Mining - Remote setup on Hetzner VPS (runs ON the server)
# Adds the Node.js virtual-mining service alongside the existing Python API.
# Safe to re-run (idempotent).
# =============================================================================
set -e

VM_DIR=/opt/obz_project/virtual-mining

echo "==> [1/6] Installing Node.js if needed"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
echo "    node $(node -v)"

echo "==> [2/6] Unpacking virtual-mining bundle to $VM_DIR"
mkdir -p "$VM_DIR/logs"
tar -xzf /tmp/vmining-bundle.tar.gz -C "$VM_DIR"
cd "$VM_DIR"
if [ -f .env.production ]; then
  mv -f .env.production .env
  chmod 600 .env
fi

echo "==> [3/6] Installing production dependencies"
npm install --omit=dev --no-audit --no-fund

echo "==> [4/6] Creating systemd service obz-vmining"
cat > /etc/systemd/system/obz-vmining.service <<'SERVICEEOF'
[Unit]
Description=OBZ Virtual Mining (Node.js)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/obz_project/virtual-mining
Environment=NODE_ENV=production
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable obz-vmining
systemctl restart obz-vmining

echo "==> [5/6] Updating nginx (add /api/vmining/ + /api/admin/withdrawals -> :4100)"
NGINX_FILE=$(grep -rl "server_name api.obzexchange.com" /etc/nginx/sites-enabled/ 2>/dev/null | head -n 1)
if [ -z "$NGINX_FILE" ]; then
  echo "    WARNING: nginx config for api.obzexchange.com not found - add locations manually from /tmp/vmining-locations.conf"
else
  echo "    Found config: $NGINX_FILE"
  cp "$NGINX_FILE" "${NGINX_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  if grep -q "api/vmining" "$NGINX_FILE"; then
    echo "    vmining locations already present - skipping insert"
  else
    sed -i '/server_name api.obzexchange.com;/r /tmp/vmining-locations.conf' "$NGINX_FILE"
    echo "    Locations inserted"
  fi
  nginx -t && systemctl reload nginx && echo "    nginx reloaded"
fi

echo "==> [6/6] Smoke test"
sleep 2
echo "    Local:  $(curl -s --max-time 5 http://127.0.0.1:4100/api/vmining/pool || echo FAILED)"
echo "    Public: $(curl -s --max-time 8 https://api.obzexchange.com/api/vmining/pool || echo FAILED)"
systemctl is-active obz-vmining && echo "    Service: active"

echo ""
echo "REMOTE SETUP DONE"
