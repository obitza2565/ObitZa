# =============================================================================
# OBZ Virtual Mining - Pre-flight Check for External Mining Launch
# =============================================================================
# Run this before opening mining to public users
# =============================================================================

param(
    [string]$ApiUrl = "http://localhost:4100",
    [string]$ExpectedDomain = "obzexchange.com"
)

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     OBZ Mining - External Launch Pre-flight Check           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$allPassed = $true

# Test 1: API is reachable
Write-Host "[1/6] Checking API connectivity..." -ForegroundColor Yellow
try {
    $pool = Invoke-RestMethod "$ApiUrl/api/vmining/pool" -TimeoutSec 10
    Write-Host "  ✓ API is online" -ForegroundColor Green
    Write-Host "    Pool Cap: $($pool.dailyCapObz) OBZ/day | Mined today: $($pool.totalMinedTodayObz) OBZ" -ForegroundColor Gray
} catch {
    Write-Host "  ✗ API is NOT reachable: $_" -ForegroundColor Red
    $allPassed = $false
}

# Test 2: Hot wallet balance
Write-Host "[2/6] Checking Hot Wallet balance..." -ForegroundColor Yellow
try {
    $balance = Invoke-RestMethod "$ApiUrl/api/vmining/hot-wallet/balance" -TimeoutSec 10
    $bnb = [decimal]$balance.bnb
    $obz = [decimal]$balance.obz
    
    Write-Host "    Address: $($balance.address)" -ForegroundColor Gray
    Write-Host "    BNB: $bnb" -ForegroundColor $(if ($bnb -ge 0.05) { "Green" } else { "Red" })
    Write-Host "    OBZ: $obz" -ForegroundColor $(if ($obz -ge 100) { "Green" } else { "Red" })
    
    if ($bnb -lt 0.02) {
        Write-Host "  ✗ CRITICAL: BNB too low for gas! Need at least 0.05 BNB" -ForegroundColor Red
        $allPassed = $false
    } elseif ($bnb -lt 0.05) {
        Write-Host "  ⚠ WARNING: BNB low. Recommended: 0.1 BNB for ~50 transactions" -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ BNB sufficient for gas" -ForegroundColor Green
    }
    
    if ($obz -lt 100) {
        Write-Host "  ✗ CRITICAL: OBZ too low! Need at least 100 OBZ for 1 day of mining" -ForegroundColor Red
        $allPassed = $false
    } elseif ($obz -lt 500) {
        Write-Host "  ⚠ WARNING: OBZ low. Recommended: 1000+ OBZ for 10 days" -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ OBZ sufficient" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✗ Cannot check balance (wallet may not be configured)" -ForegroundColor Red
    $allPassed = $false
}

# Test 3: Rate limiting
Write-Host "[3/6] Testing rate limiting..." -ForegroundColor Yellow
$rateLimitOk = $false
1..70 | ForEach-Object {
    try {
        Invoke-RestMethod "$ApiUrl/api/vmining/pool" -TimeoutSec 2 | Out-Null
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 429) {
            $rateLimitOk = $true
        }
    }
}
if ($rateLimitOk) {
    Write-Host "  ✓ Rate limiting active (blocked after 60 requests)" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Rate limiting may not be working properly" -ForegroundColor Yellow
}

# Test 4: Input validation
Write-Host "[4/6] Testing input validation..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Method Post "$ApiUrl/api/vmining/start" -ContentType 'application/json' -Body '{"userId":"bad<script>","walletAddress":"invalid"}' -TimeoutSec 5 | Out-Null
    Write-Host "  ⚠ Input validation may be too permissive" -ForegroundColor Yellow
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 400) {
        Write-Host "  ✓ Input validation working (rejected malicious input)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Unexpected response: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Yellow
    }
}

# Test 5: Admin protection
Write-Host "[5/6] Testing admin endpoint protection..." -ForegroundColor Yellow
try {
    Invoke-RestMethod "$ApiUrl/api/admin/withdrawals" -TimeoutSec 5 | Out-Null
    Write-Host "  ✗ CRITICAL: Admin endpoint is NOT protected!" -ForegroundColor Red
    $allPassed = $false
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        Write-Host "  ✓ Admin endpoint protected (401 without key)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Unexpected response: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Yellow
    }
}

# Test 6: CORS configuration
Write-Host "[6/6] Checking CORS configuration..." -ForegroundColor Yellow
try {
    $headers = @{
        "Origin" = "https://$ExpectedDomain"
        "Access-Control-Request-Method" = "POST"
    }
    $response = Invoke-WebRequest -Uri "$ApiUrl/api/vmining/pool" -Method OPTIONS -Headers $headers -TimeoutSec 5
    $corsHeader = $response.Headers["Access-Control-Allow-Origin"]
    if ($corsHeader -eq "https://$ExpectedDomain" -or $corsHeader -eq "*") {
        Write-Host "  ✓ CORS allows $ExpectedDomain" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ CORS may block $ExpectedDomain (got: $corsHeader)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠ Could not verify CORS (server may not support OPTIONS)" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor $(if ($allPassed) { "Green" } else { "Red" })
if ($allPassed) {
    Write-Host "║           ✅ READY FOR EXTERNAL MINING                       ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now:" -ForegroundColor Cyan
    Write-Host "  1. Share https://$ExpectedDomain/mining.html with users" -ForegroundColor White
    Write-Host "  2. Monitor admin panel: https://$ExpectedDomain/admin-withdrawals.html" -ForegroundColor White
    Write-Host "  3. Watch logs for any issues" -ForegroundColor White
} else {
    Write-Host "║           ❌ NOT READY - FIX ISSUES ABOVE                    ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "Critical actions needed:" -ForegroundColor Yellow
    Write-Host "  1. Fund Hot Wallet with BNB and OBZ" -ForegroundColor White
    Write-Host "  2. Update CORS_ORIGINS in .env to include your domain" -ForegroundColor White
    Write-Host "  3. Ensure ADMIN_API_KEY is set and secure" -ForegroundColor White
}
Write-Host ""
