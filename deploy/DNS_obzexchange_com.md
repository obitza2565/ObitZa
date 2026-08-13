# DNS records for obzexchange.com

Use these records at your registrar DNS panel (or Cloudflare DNS if you delegate nameservers there).

## Required records

1. Root website
- Type: A (create all four records)
- Name/Host: @
- Values: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
- TTL: 300

2. WWW alias
- Type: CNAME
- Name/Host: www
- Value: `obitza2565.github.io`
- TTL: 300

3. API endpoint
- Type: A
- Name/Host: api
- Value: <YOUR_VPS_PUBLIC_IP>
- TTL: 300

## Optional records

4. Admin endpoint (if separated)
- Type: CNAME
- Name/Host: admin
- Value: obzexchange.com
- TTL: 300

5. Status page (if used)
- Type: CNAME
- Name/Host: status
- Value: obzexchange.com
- TTL: 300

## Verification commands

After DNS propagation:

- nslookup api.obzexchange.com
- nslookup www.obzexchange.com

Then on VPS:

- sudo bash deploy/setup_nginx_tls.sh api.obzexchange.com
- bash deploy/smoke_test_api.sh https://api.obzexchange.com

Finally on local machine:

- powershell -ExecutionPolicy Bypass -File deploy\set_api_base.ps1 -ApiBase "https://api.obzexchange.com"
- powershell -ExecutionPolicy Bypass -File deploy\preflight_check.ps1 -ApiBase "https://api.obzexchange.com" -ExpectedDomain "api.obzexchange.com" -RequireHttps
