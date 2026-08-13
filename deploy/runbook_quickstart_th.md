# Runbook เร็ว (ประหยัดเครดิต)

## 1) ตั้ง API base ครั้งเดียว
บนเครื่อง Windows:

powershell -ExecutionPolicy Bypass -File deploy\set_api_base.ps1 -ApiBase "https://api.obzexchange.com"

## 2) เช็กก่อน deploy (Preflight)

powershell -ExecutionPolicy Bypass -File deploy\preflight_check.ps1 -ApiBase "https://api.obzexchange.com" -ExpectedDomain "api.obzexchange.com" -RequireHttps

ถ้าเห็น Preflight passed ค่อย deploy frontend รอบจริง

## 3) ฝั่ง VPS (หลังอัปโหลดโค้ด)

cd /opt/obz_project
sudo bash deploy/vps_bootstrap.sh
sudo bash deploy/setup_nginx_tls.sh api.obzexchange.com
bash deploy/smoke_test_api.sh https://api.obzexchange.com

## 4) ตรวจ flow หลัก
- Mining start/stop
- Payout request
- Admin login
- Approve / Reject / Mark as Paid
- Leaderboard refresh

## 5) หลักการลดเครดิต
- แก้โค้ดให้ครบก่อน
- local test ก่อนเสมอ
- production deploy รอบใหญ่ครั้งเดียว
