#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-}"
CONF_SRC="${CONF_SRC:-deploy/nginx-obz-api.conf}"
CONF_DST="/etc/nginx/sites-available/obz-api"

if [[ -z "${DOMAIN}" ]]; then
  echo "Usage: sudo bash deploy/setup_nginx_tls.sh api.your-domain.com"
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/setup_nginx_tls.sh ${DOMAIN}"
  exit 1
fi

if [[ ! -f "${CONF_SRC}" ]]; then
  echo "Cannot find ${CONF_SRC}"
  exit 1
fi

echo "Configuring nginx for ${DOMAIN}..."
sed "s/api.example.com/${DOMAIN}/g" "${CONF_SRC}" > "${CONF_DST}"
ln -sf "${CONF_DST}" /etc/nginx/sites-enabled/obz-api
nginx -t
systemctl reload nginx

echo "Installing certbot and requesting TLS certificate..."
apt update
apt install -y certbot python3-certbot-nginx
certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "admin@${DOMAIN}" --redirect || {
  echo "Certbot failed. Check DNS A record for ${DOMAIN} and retry."
  exit 1
}

echo "Done. HTTPS enabled for ${DOMAIN}."
