# OBZ Migration (Credit Saver)

## 1) Prepare once in local
- Update `exchange/app-config.js` with your API URL.
- Verify pages locally: trade, mining, admin, leaderboard.
- Do not deploy until all checks pass.

## 2) VPS setup (Ubuntu)
```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip nginx
sudo mkdir -p /opt/obz_project
sudo chown -R $USER:$USER /opt/obz_project
```

## 3) Upload project and install Python deps
```bash
cd /opt/obz_project
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install fastapi uvicorn
```

If you have more dependencies, install them too.

## 4) Fast path (recommended)
Run these scripts after code upload to `/opt/obz_project`:

```bash
cd /opt/obz_project
sudo bash deploy/vps_bootstrap.sh
sudo bash deploy/setup_nginx_tls.sh api.obzexchange.com
bash deploy/smoke_test_api.sh https://api.obzexchange.com
```

Before using the admin payout page in production, create a random admin key:

```bash
printf 'OBZ_ADMIN_API_KEY=%s\n' "$(openssl rand -hex 32)" | sudo tee /opt/obz_project/.env >/dev/null
sudo chown www-data:www-data /opt/obz_project/.env
sudo chmod 600 /opt/obz_project/.env
sudo systemctl restart obz-api
```

## 5) Manual systemd service (optional)
```bash
sudo cp deploy/obz-api.service /etc/systemd/system/obz-api.service
sudo systemctl daemon-reload
sudo systemctl enable obz-api
sudo systemctl restart obz-api
sudo systemctl status obz-api --no-pager
```

## 6) Manual nginx (optional)
- Copy `deploy/nginx-obz-api.conf` to `/etc/nginx/sites-available/obz-api`.
- Replace `api.obzexchange.com` if you choose another API subdomain.

```bash
sudo ln -s /etc/nginx/sites-available/obz-api /etc/nginx/sites-enabled/obz-api
sudo nginx -t
sudo systemctl reload nginx
```

## 7) Manual HTTPS (optional)
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.obzexchange.com
```

## 8) Verify backend
```bash
curl https://api.obzexchange.com/docs
curl https://api.obzexchange.com/api/mining/network
```

## 9) Deploy frontend once
- Deploy static `exchange/` to Cloudflare Pages or GitHub Pages.
- Keep deploy count low: one final deploy after local validation.

## 10) Set frontend API base once
On your Windows machine:

```powershell
powershell -ExecutionPolicy Bypass -File deploy\set_api_base.ps1 -ApiBase "https://api.example.com"
```

Run preflight before your one-shot frontend deploy:

```powershell
powershell -ExecutionPolicy Bypass -File deploy\set_api_base.ps1 -ApiBase "https://api.obzexchange.com"
```

```powershell
powershell -ExecutionPolicy Bypass -File deploy\preflight_check.ps1 -ApiBase "https://api.obzexchange.com" -ExpectedDomain "api.obzexchange.com" -RequireHttps
```

## 11) Final checks
- Mining start/stop works.
- Payout request is created.
- Admin login, approve, mark paid, and audit logs work.
- Leaderboard refresh works.
