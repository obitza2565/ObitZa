# OBZ Virtual Mining — คู่มือติดตั้งบน Hetzner (Deployment Guide)

ระบบ Virtual Mining จำลองด้วย Node.js/TypeScript — แจกเหรียญ OBZ ตามเวลา (Timer-based)
ไม่ใช้ GPU/CPU ขุดจริง, ราคา Fixed 1 OBZ = 1 USDT, Mining Cap รวมทุกคน 100 OBZ/วัน
จ่ายเหรียญผ่าน Hot Wallet บน BNB Chain โดยเชื่อมต่อ **Public RPC ภายนอกเท่านั้น**
(ไม่รันโหนดคริปโตบนเซิร์ฟเวอร์ ตามนโยบาย Hetzner)

---

## 1) เตรียมเซิร์ฟเวอร์ (Ubuntu 22.04/24.04)

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs nginx certbot python3-certbot-nginx apache2-utils
node -v   # ควรได้ v20.x
```

## 2) อัปโหลดโค้ดและติดตั้ง dependencies

```bash
sudo mkdir -p /opt/obz && sudo chown $USER:$USER /opt/obz
# อัปโหลดโฟลเดอร์ virtual-mining ขึ้นเซิร์ฟเวอร์ (scp/git clone จาก repo ส่วนตัว)
cd /opt/obz/virtual-mining
npm ci          # หรือ npm install
npm run build   # คอมไพล์ TypeScript -> dist/
```

## 3) ตั้งค่าไฟล์ .env (เก็บความลับทั้งหมดที่นี่เท่านั้น)

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

ค่าที่ **ต้อง** ใส่เอง:

| ตัวแปร | คำอธิบาย |
|---|---|
| `HOT_WALLET_PRIVATE_KEY` | Private key ของกระเป๋าจ่ายเหรียญ (ห้าม commit ขึ้น GitHub เด็ดขาด) |
| `OBZ_TOKEN_ADDRESS` | ที่อยู่สัญญา OBZ Token บน BNB Chain |
| `ADMIN_API_KEY` | รหัสลับสำหรับหน้าแอดมินอนุมัติถอนเงิน (ตั้งให้ยาวและสุ่ม) |
| `ALERT_WEBHOOK_URL` | Webhook Discord/Slack สำหรับแจ้งเตือนยอดเงินต่ำ |
| `CORS_ORIGINS` | โดเมนหน้าเว็บ เช่น `https://obzexchange.com` |

ค่าปรับได้ตามงบประมาณ: `DAILY_MINING_CAP_OBZ=100`, `OBZ_PRICE_USDT=1`,
`WITHDRAWAL_APPROVAL_THRESHOLD_USDT=50`, `MIN_BNB_GAS_BALANCE=0.02`

> ⚠️ ห้ามเปลี่ยน `BSC_RPC_URL` ไปชี้โหนดบนเซิร์ฟเวอร์ตัวเอง — ใช้ Public RPC เท่านั้น
> เช่น `https://bsc-dataseed.binance.org/` หรือ RPC เสิร์ฟพิเศษ (NodeReal/Ankr)

## 4) รันเป็นระบบอัตโนมัติด้วย systemd

สร้างไฟล์ `/etc/systemd/system/obz-vmining.service`:

```ini
[Unit]
Description=OBZ Virtual Mining Service
After=network.target

[Service]
WorkingDirectory=/opt/obz/virtual-mining
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
# โหลดค่าลับจาก .env (dotenv ในโค้ดอ่านเองจาก WorkingDirectory)

[Install]
WantedBy=multi-user.target
```

เปิดใช้งาน:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now obz-vmining
sudo systemctl status obz-vmining
journalctl -u obz-vmining -f   # ดู log สด
```

## 5) ตั้ง nginx หน้าบ้าน + TLS + Basic Auth

เพิ่ม site ใหม่ `/etc/nginx/sites-available/obz-vmining` (proxy เข้าพอร์ต 4100):

```nginx
server {
    listen 80;
    server_name api.obzexchange.com;

    location /api/vmining/ {
        proxy_pass http://127.0.0.1:4100;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

ส่วนเว็บหลัก `obzexchange.com` (ไฟล์ static) ให้ล็อกด้วย HTTP Basic Auth
เพื่อให้เฉพาะกลุ่มเพื่อนที่รู้รหัสเข้าได้:

```bash
sudo htpasswd -c /etc/nginx/.htpasswd friend1   # ตั้งรหัสผ่าน (ทำเอง ห้ามส่งรหัสผ่านให้ AI)
```

```nginx
server {
    listen 443 ssl;
    server_name obzexchange.com;
    root /var/www/obzexchange;

    auth_basic "OBZ Private";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / { try_files $uri $uri/ =404; }
}
```

ออกใบรับรอง TLS และเปิดใช้งาน:

```bash
sudo ln -s /etc/nginx/sites-available/obz-vmining /etc/nginx/sites-enabled/
sudo certbot --nginx -d obzexchange.com -d api.obzexchange.com
sudo nginx -t && sudo systemctl reload nginx
```

> หมายเหตุ: API มี Rate Limit 60 req/นาที/IP ในตัวอยู่แล้ว และเมื่อรันหลัง nginx
> ให้คงค่า `TRUST_PROXY_HOPS=1` ไว้ เพื่อให้นับ IP จริงของผู้ใช้จาก `X-Forwarded-For`

## 6) เติมเงินกระเป๋า Hot Wallet (ทำเองด้วยมือเท่านั้น)

1. ดูเลขกระเป๋า: `curl http://127.0.0.1:4100/api/vmining/hot-wallet/balance`
2. โอน **BNB** (ค่าแก๊ส แนะนำ ~0.05–0.1 BNB) และ **OBZ** (เงินทุนจ่ายผู้ขุด)
   เข้าเลขกระเป๋าดังกล่าวจากกระเป๋าส่วนตัวของคุณเอง
3. ระบบจะแจ้งเตือนอัตโนมัติผ่าน webhook หาก BNB < `MIN_BNB_GAS_BALANCE`
   หรือ OBZ < `MIN_OBZ_HOT_WALLET_BALANCE`

## 7) ทดสอบหลังติดตั้ง (Smoke Test)

```bash
# สถานะ pool (cap 100 OBZ/วัน, ราคา 1 USDT)
curl https://api.obzexchange.com/api/vmining/pool

# เริ่มขุด
curl -X POST https://api.obzexchange.com/api/vmining/start \
  -H "Content-Type: application/json" \
  -d '{"userId":"friend1","walletAddress":"0x..."}'

# เช็กยอด
curl https://api.obzexchange.com/api/vmining/status/friend1

# แอดมินดูคำขอถอนที่รออนุมัติ (ถอนเกิน 50 USDT จะเข้าคิว PENDING)
curl https://api.obzexchange.com/api/admin/withdrawals?status=PENDING \
  -H "x-admin-key: <ADMIN_API_KEY>"

# อนุมัติ / ปฏิเสธ
curl -X POST https://api.obzexchange.com/api/admin/withdrawals/<id>/approve -H "x-admin-key: <ADMIN_API_KEY>"
curl -X POST https://api.obzexchange.com/api/admin/withdrawals/<id>/reject  -H "x-admin-key: <ADMIN_API_KEY>"
```

## 8) ตำแหน่ง Log สำหรับตรวจสอบย้อนหลัง

- `virtual-mining/logs/activity.log` — การเข้าใช้งาน เริ่ม/หยุดขุด ถอนเงิน rate limit
- `virtual-mining/logs/error.log` — error ทั้งหมด เช่น การโอนล้มเหลว
- `journalctl -u obz-vmining` — log ระดับ service

## Checklist ความปลอดภัยก่อนเปิดใช้จริง

- [ ] ไฟล์ `.env` อยู่ใน `.gitignore` และไม่เคยถูก push ขึ้น GitHub
- [ ] `ADMIN_API_KEY` ยาวและสุ่ม ไม่ซ้ำกับรหัสอื่น
- [ ] เปิด Basic Auth บน nginx สำหรับเว็บหลักแล้ว
- [ ] กระเป๋า Hot Wallet เก็บเงินเท่าที่จำเป็น (ไม่ใช่กระเป๋าหลัก)
- [ ] ทดสอบ webhook แจ้งเตือนยอดเงินต่ำแล้ว
- [ ] ทดสอบถอนเงินยอดเกิน 50 USDT แล้วเข้าคิว PENDING รออนุมัติจริง
