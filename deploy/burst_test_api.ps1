$ok = 0
$limited = 0
foreach ($i in 1..80) {
  $code = curl.exe -s -o NUL -w "%{http_code}" "https://api.obzexchange.com/api/vmining/pool"
  if ($code -eq "200") { $ok++ }
  elseif ($code -eq "429") { $limited++ }
}
Write-Output "RESULT ok=$ok limited=$limited"
