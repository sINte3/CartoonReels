# v3_balance_check.ps1 — бесплатно: текущий баланс Kie против расхода по записям задач пакета.
. (Join-Path $PSScriptRoot 'v3_lib.ps1')
Set-Key
try {
  $bal = Get-Balance
  Assert-Balance $bal
  $sp = Get-Spend
  'balance=' + $bal.ToString([Globalization.CultureInfo]::InvariantCulture) + ' actual=' + $sp.actual + ' pending=' + $sp.pending + ' images=' + $sp.image + ' (retry ' + $sp.imageRetry + ') videos=' + $sp.video + ' (retry ' + $sp.videoRetry + ')'
} finally { $env:KIE_API_KEY = $null }
