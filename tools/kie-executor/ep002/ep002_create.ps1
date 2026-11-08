# ep002_create.ps1 -Label K0|K1|A|K2|B|<этап>-retryN [-AddendumFile f] — ПЛАТНО: одна отправка createTask для одного этапа пакета EP002.
param([Parameter(Mandatory)][string]$Label, [string]$AddendumFile = '')
. (Join-Path $PSScriptRoot 'ep002_lib.ps1')
if ($AddendumFile -and $Label -notmatch '-retry\d+$') { throw 'Правка промпта допускается только для адресного повтора.' }
if ($AddendumFile -and -not (Test-Path -LiteralPath $AddendumFile)) { throw ('Нет файла правки ' + $AddendumFile) }
$stage = $Label -replace '-retry\d+$', ''
if (-not $Stages.Contains($stage)) { throw ('Неизвестный этап ' + $stage) }
$kind = $Stages[$stage].kind
$price = [double]$Stages[$stage].price
$after = [double]$Stages[$stage].after
$attemptType = if ($Label -match '-retry\d+$') { 'retry' } else { 'base' }
$journal = Read-Journal
$reason = $null
$lastDec = @($journal | Where-Object { $_.type -in 'accept', 'reject' -and $_.stage -eq $stage }) | Select-Object -Last 1
if ($attemptType -eq 'retry') {
  if (-not $lastDec -or $lastDec.type -ne 'reject') { throw ('Повтор ' + $Label + ' возможен только после записанного отказа от предыдущей попытки ' + $stage + ' с конкретным дефектом.') }
  $reason = $lastDec.reason
} elseif (@($journal | Where-Object { $_.type -eq 'intent' -and $_.stage -eq $stage }).Count) { throw ('Базовая попытка ' + $stage + ' уже отправлялась.') }

function Get-Accepted([string]$st) {
  $a = @(Read-Journal | Where-Object { $_.type -in 'accept', 'reject' -and $_.stage -eq $st }) | Select-Object -Last 1
  if (-not $a -or $a.type -ne 'accept') { throw ('Этап ' + $st + ' не принят — ' + $stage + ' не запускаю.') }
  if ((Get-Sha $a.file) -ne $a.sha256) { throw ('Файл принятого ' + $st + ' изменился: ' + $a.file) }
  $a
}
function Get-ALast {
  $acc = Get-Accepted 'A'
  $e = @(Read-Journal | Where-Object { $_.type -eq 'alast' -and $_.sourceSha256 -eq $acc.sha256 }) | Select-Object -Last 1
  if (-not $e) { throw 'Нет извлечённого последнего кадра принятого A.' }
  if ((Get-Sha $e.file) -ne $e.sha256) { throw ('Последний кадр A изменился: ' + $e.file) }
  $e
}

# Все запреты — до загрузок
[void](Assert-CanCreate $Label $kind $attemptType $price $after)
switch ($stage) {
  'K0' { $need = @() }
  'K1' { $need = @(Get-Accepted 'K0') }
  'A' { $need = @((Get-Accepted 'K0'), (Get-Accepted 'K1')) }
  'K2' { $need = @((Get-ALast), (Get-Accepted 'K0')) }
  'B' { $need = @((Get-ALast), (Get-Accepted 'K2')) }
}
Set-Key
try {
  Assert-Balance (Get-Balance)
  $map = @{}; $inputs = [ordered]@{}
  function Add-Input([string]$ph, [string]$name, [string]$file, [string]$sha) {
    $url = Send-Upload $file $sha
    $map[$ph] = $url
    $inputs[$name] = [ordered]@{ file = $file; sha256 = $sha; url = $url }
  }
  switch ($stage) {
    'K0' { Add-Input $Ph.hero 'hero' $Hero $HeroSha }
    'K1' { Add-Input $Ph.K0 'K0' $need[0].file $need[0].sha256; Add-Input $Ph.hero 'hero' $Hero $HeroSha }
    'A' { Add-Input $Ph.K0 'K0' $need[0].file $need[0].sha256; Add-Input $Ph.K1 'K1' $need[1].file $need[1].sha256 }
    'K2' { Add-Input $Ph.ALast 'A-last' $need[0].file $need[0].sha256; Add-Input $Ph.K0 'K0' $need[1].file $need[1].sha256; Add-Input $Ph.hero 'hero' $Hero $HeroSha }
    'B' { Add-Input $Ph.ALast 'A-last' $need[0].file $need[0].sha256; Add-Input $Ph.K2 'K2' $need[1].file $need[1].sha256 }
  }
  $built = Build-Body $stage $map $AddendumFile
  $runFile = New-Task -Label $Label -Stage $stage -Kind $kind -Built $built -Expected $price -After $after -Inputs $inputs -AttemptType $attemptType -Reason $reason
  $run = Read-Run $runFile
  'Задача создана: ' + $Label + ' taskId ' + $run.taskId + ' | ' + $run.model + ' | ожидается ' + $run.priceCr + ' кр | бюджет: ' + ($run.budget | ConvertTo-Json -Compress)
  'Запись: ' + $runFile
} finally { $env:KIE_API_KEY = $null }
