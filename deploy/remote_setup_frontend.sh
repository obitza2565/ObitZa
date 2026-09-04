#!/bin/bash
# =============================================================================
# OBZ Frontend - Serve obzexchange.com from VPS nginx with Basic Auth + SSL
# Runs ON the VPS. Idempotent (safe to re-run).
# =============================================================================
set -e

WEB_ROOT=/var/www/obzexchange
DOMAIN=obzexchange.com

echo "==> [1/5] Unpacking frontend to $WEB_ROOT"
mkdir -p "$WEB_ROOT"
tar -xzf /tmp/frontend-bundle.tar.gz -C "$WEB_ROOT"
chown -R www-data:www-data "$WEB_ROOT"
echo "    Files: $(ls -1 $WEB_ROOT | head -20 | tr '\n' ' ')"

echo "==> [2/5] Setting up Basic Auth (user: obz)"
if [ ! -f /etc/nginx/.htpasswd ]; then
  # Create with a random password, printed once for the owner
  RANDOMPASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
  apt-get install -y apache2-utils >/dev/null 2>&1
  htpasswd -cb /etc/nginx/.htpasswd obz "$RANDOMPASS"
  echo "    =========================================="
  echo "    BASIC AUTH  user: obz   pass: $RANDOMPASS"
  echo "    (save this - change later with: htpasswd /etc/nginx/.htpasswd obz)"
  echo "    =========================================="
else
  echo "    .htpasswd already exists - keeping current password"
fi

echo "==> [3/5] Writing nginx config for $DOMAIN"
cat > /etc/nginx/sites-available/obz-frontend <<'NGINXEOF'
server {
    listen 80;
    server_name obzexchange.com www.obzexchange.com;

    root /var/www/obzexchange;
    index index.html;

    # Basic Auth - only your group can enter
    auth_basic "OBZ Private";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        try_files $uri $uri/ =404;
    }

    # Static asset caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
        expires 1h;
        add_header Cache-Control "public";
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/obz-frontend /etc/nginx/sites-enabled/obz-frontend
nginx -t && systemctl reload nginx
echo "    nginx configured and reloaded"

echo "==> [4/5] Setting up SSL (HTTPS) with Let's Encrypt"
if [ -d /etc/letsencrypt/live/obzexchange.com ]; then
  echo "    SSL cert already exists - skipping"
else
  echo "    Requesting certificate for the apex domain (requires DNS A record -> this server)..."
  certbot --nginx -d obzexchange.com --non-interactive --agree-tos --register-unsafely-without-email --redirect || \
    echo "    SSL failed (DNS may not point here yet) - re-run after DNS propagation: certbot --nginx -d obzexchange.com"
fi

echo "==> [5/5] Verify"
echo "    Local test: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/ -H 'Host: obzexchange.com' -u obz:test || echo 'check auth')"
echo "    Web root contents: $(ls -1 $WEB_ROOT | wc -l) files"

echo ""
echo "FRONTEND SETUP DONE"
