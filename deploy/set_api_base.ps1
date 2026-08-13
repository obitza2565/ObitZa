param(
  [Parameter(Mandatory = $true)]
  [string]$ApiBase
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'exchange\app-config.js'

if (-not (Test-Path $configPath)) {
  throw "Cannot find config file: $configPath"
}

$cleanBase = $ApiBase.TrimEnd('/')
$content = @"
window.OBZ_CONFIG = {
  // Set this once after migration, for example:
  // apiBase: 'https://api.your-domain.com'
  apiBase: '$cleanBase',
};
"@

Set-Content -Path $configPath -Value $content -Encoding UTF8
Write-Host "Updated API base in $configPath => $cleanBase"
