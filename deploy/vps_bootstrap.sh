#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/obz_project}"
APP_USER="${APP_USER:-www-data}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/vps_bootstrap.sh"
  exit 1
fi

echo "[1/6] Installing OS packages..."
apt update
apt install -y python3 python3-venv python3-pip nginx curl

echo "[2/6] Creating app directory: ${APP_DIR}"
mkdir -p "${APP_DIR}"

if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  echo "User ${APP_USER} not found, creating..."
  useradd --system --create-home --shell /usr/sbin/nologin "${APP_USER}"
fi

chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"

echo "[3/6] Creating Python virtual environment..."
sudo -u "${APP_USER}" "${PYTHON_BIN}" -m venv "${APP_DIR}/.venv"

echo "[4/6] Installing Python dependencies..."
sudo -u "${APP_USER}" "${APP_DIR}/.venv/bin/pip" install --upgrade pip
if [[ -f "${APP_DIR}/requirements.txt" ]]; then
  sudo -u "${APP_USER}" "${APP_DIR}/.venv/bin/pip" install -r "${APP_DIR}/requirements.txt"
else
  sudo -u "${APP_USER}" "${APP_DIR}/.venv/bin/pip" install fastapi uvicorn
fi

echo "[5/6] Installing systemd service..."
cp "${APP_DIR}/deploy/obz-api.service" /etc/systemd/system/obz-api.service
systemctl daemon-reload
systemctl enable obz-api
systemctl restart obz-api

echo "[6/6] Verifying service..."
systemctl --no-pager --full status obz-api || true
curl -fsS "http://127.0.0.1:8080/docs" >/dev/null && echo "OK: API docs reachable on localhost:8080"

echo "Bootstrap done. Next: configure nginx and TLS."
