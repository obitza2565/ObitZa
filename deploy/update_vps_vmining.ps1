# =============================================================================
# OBZ Virtual Mining - Update deploy to Hetzner VPS
# Builds locally, uploads, installs service, patches nginx, smoke-tests.
# You will be asked for the VPS root password TWICE (scp + ssh).
# Usage: powershell -ExecutionPolicy Bypass -File deploy\update_vps_vmining.ps1
# =============================================================================
param(
  [string]$VpsIp = "157.180.30.86",
  [string]$SshUser = "root"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vmDir = Join-Path $root 'virtual-mining'

Write-Host "=== OBZ vmining update deploy -> $VpsIp ===" -ForegroundColor Cyan

Write-Host "[1/5] Building TypeScript..."
Push-Location $vmDir
node node_modules\typescript\bin\tsc -p tsconfig.json
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "TypeScript build failed" }

Write-Host "[2/5] Preparing production .env (CORS -> obzexchange.com)..."
$envRaw = Get-Content .env -Raw
$envRaw = $envRaw -replace '(?m)^CORS_ORIGINS=.*$', 'CORS_ORIGINS=https://obzexchange.com,https://www.obzexchange.com'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path (Get-Location) '.env.production'), $envRaw, $utf8NoBom)

Write-Host "[3/5] Creating bundle..."
# bsdtar cannot write into the Thai-named OneDrive path, so build in %TEMP%.
$bundle = Join-Path $env:TEMP 'vmining-bundle.tar.gz'
if (Test-Path $bundle) { Remove-Item $bundle -Force }
tar -czf $bundle dist package.json .env.production
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "tar failed" }
Pop-Location

Write-Host "[4/5] Uploading bundle to VPS (type the root password when asked)..."
$bundleArg = '"' + $bundle + '"'
$setupArg  = '"' + (Join-Path $PSScriptRoot 'remote_setup_vmining.sh') + '"'
$locArg    = '"' + (Join-Path $PSScriptRoot 'vmining-locations.conf') + '"'
scp $bundleArg $setupArg $locArg "${SshUser}@${VpsIp}:/tmp/"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

Write-Host "[5/5] Running remote setup (type the root password once more)..."
ssh "${SshUser}@${VpsIp}" "bash /tmp/remote_setup_vmining.sh"
if ($LASTEXITCODE -ne 0) { throw "remote setup failed" }

Write-Host ""
Write-Host "DEPLOY OK - verify:" -ForegroundColor Green
Write-Host "  https://api.obzexchange.com/api/vmining/pool"
Write-Host "  Then update the Netlify frontend (exchange/ folder) so mining.html goes live."
