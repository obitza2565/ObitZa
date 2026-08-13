param(
  [Parameter(Mandatory = $true)]
  [string]$ApiBase,

  [Parameter(Mandatory = $false)]
  [string]$ExpectedDomain = "",

  [Parameter(Mandatory = $false)]
  [switch]$RequireHttps
)

$ErrorActionPreference = 'Stop'

function Write-Ok($msg){ Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg){ Write-Host "[FAIL] $msg" -ForegroundColor Red }

$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot 'exchange\app-config.js'

if (-not (Test-Path $configPath)) {
  Write-Fail "Cannot find config file: $configPath"
  exit 1
}

$api = $ApiBase.TrimEnd('/')
if ($RequireHttps -and -not $api.StartsWith('https://')) {
  Write-Fail "RequireHttps is enabled but ApiBase is not https: $api"
  exit 1
}

try {
  $uri = [System.Uri]$api
} catch {
  Write-Fail "Invalid ApiBase URL: $api"
  exit 1
}

if ($uri.Host -in @('127.0.0.1', 'localhost')) {
  Write-Warn "ApiBase points to localhost. Good for local test, not for public deployment."
} else {
  Write-Ok "ApiBase host: $($uri.Host)"
}

if ($ExpectedDomain) {
  if ($uri.Host -ne $ExpectedDomain) {
    Write-Warn "ApiBase host ($($uri.Host)) does not match ExpectedDomain ($ExpectedDomain)."
  } else {
    Write-Ok "ApiBase host matches ExpectedDomain"
  }
}

# Check app-config.js contains the target base
$configText = Get-Content -Path $configPath -Raw
if ($configText -match [Regex]::Escape($api)) {
  Write-Ok "app-config.js contains the provided ApiBase"
} else {
  Write-Warn "app-config.js does not contain the provided ApiBase. Run deploy/set_api_base.ps1 first."
}

# DNS check for non-local host
if ($uri.Host -notin @('127.0.0.1', 'localhost')) {
  try {
    $dns = Resolve-DnsName -Name $uri.Host -Type A -ErrorAction Stop
    $ips = $dns | Select-Object -ExpandProperty IPAddress
    if ($ips) {
      Write-Ok "DNS A record found: $($ips -join ', ')"
    } else {
      Write-Warn "DNS query returned no A records"
    }
  } catch {
    Write-Warn "DNS lookup failed for $($uri.Host): $($_.Exception.Message)"
  }
}

$paths = @('/docs', '/api/mining/network', '/api/mining/leaderboard?limit=5')
$failed = $false
foreach($p in $paths){
  $url = "$api$p"
  try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
      Write-Ok "HTTP $($resp.StatusCode) $p"
    } else {
      Write-Warn "HTTP $($resp.StatusCode) $p"
      $failed = $true
    }
  } catch {
    Write-Fail "Request failed: $url"
    Write-Fail $_.Exception.Message
    $failed = $true
  }
}

if ($failed) {
  Write-Fail "Preflight finished with failures"
  exit 2
}

Write-Ok "Preflight passed"
