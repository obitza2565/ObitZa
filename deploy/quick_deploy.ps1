# Quick Deploy - Just update code without full setup
# Usage: .\quick_deploy.ps1 -VpsIp "123.123.123.123"

param(
    [Parameter(Mandatory=$true)]
    [string]$VpsIp,
    [string]$SshUser = "root"
)

Write-Host "🚀 Quick deploying to $VpsIp..." -ForegroundColor Cyan

# Build locally
Set-Location virtual-mining
node node_modules\typescript\bin\tsc -p tsconfig.json
Set-Location ..

# Upload only changed files
Write-Host "📤 Uploading..." -ForegroundColor Yellow
scp -r virtual-mining\dist "${SshUser}@${VpsIp}:/opt/obz/virtual-mining/"
scp virtual-mining\package.json "${SshUser}@${VpsIp}:/opt/obz/virtual-mining/"

# Restart service
Write-Host "🔄 Restarting service..." -ForegroundColor Yellow
ssh "${SshUser}@${VpsIp}" "systemctl restart obz-vmining && sleep 2 && systemctl status obz-vmining --no-pager"

Write-Host "✅ Done! Check https://your-domain.com/mining.html" -ForegroundColor Green
