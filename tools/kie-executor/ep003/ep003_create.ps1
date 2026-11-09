# ep003_create.ps1 -Label K0|K1|C|K2|D|<этап>-retryN [-AddendumFile f] — ПЛАТНО: одна отправка createTask для одного этапа пакета EP003.
# Граф: K0 ← кадр 167 начала, герой; K1 ← K0, кадр 167 начала, герой; C ← first K0 / last K1;
#       K2 ← фактический кадр 119 принятого C, K0, герой; D ← first K2 (без last_frame_url).
param([Parameter(Mandatory)][string]$Label, [string]$AddendumFile = '')
. (Join-Path $PSScriptRoot 'ep003_lib.ps1')
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
function Get-CLast {
  $acc = Get-Accepted 'C'
  $e = @(Read-Journal | Where-Object { $_.type -eq 'clast' -and $_.sourceSha256 -eq $acc.sha256 }) | Select-Object -Last 1
  if (-not $e) { throw 'Нет извлечённого последнего кадра (119) принятого C.' }
  if ((Get-Sha $e.file) -ne $e.sha256) { throw ('Последний кадр C изменился: ' + $e.file) }
  $e
}
function Assert-OpeningLast { if ((Get-Sha $OpeningLast) -ne $OpeningLastSha) { throw 'Кадр 167 начала не совпал по SHA-256 — export-inputs.ps1.' } }

# Все запреты — до загрузок
[void](Assert-CanCreate $Label $kind $attemptType $price $after)
switch ($stage) {
  'K0' { Assert-OpeningLast; $need = @() }
  'K1' { Assert-OpeningLast; $need = @(Get-Accepted 'K0') }
  'C' { $need = @((Get-Accepted 'K0'), (Get-Accepted 'K1')) }
  'K2' { $need = @((Get-CLast), (Get-Accepted 'K0')) }
  'D' { [void](Get-CLast); $need = @(Get-Accepted 'K2') }
}
Set-Key
try {
  [void](Assert-Balance (Get-Balance))
  $map = @{}; $inputs = [ordered]@{}
  function Add-Input([string]$ph, [string]$name, [string]$file, [string]$sha) {
    $url = Send-Upload $file $sha
    $map[$ph] = $url
    $inputs[$name] = [ordered]@{ file = $file; sha256 = $sha; url = $url }
  }
  switch ($stage) {
    'K0' { Add-Input $Ph.opening 'opening-last' $OpeningLast $OpeningLastSha; Add-Input $Ph.hero 'hero' $Hero $HeroSha }
    'K1' { Add-Input $Ph.K0 'K0' $need[0].file $need[0].sha256; Add-Input $Ph.opening 'opening-last' $OpeningLast $OpeningLastSha; Add-Input $Ph.hero 'hero' $Hero $HeroSha }
    'C' { Add-Input $Ph.K0 'K0' $need[0].file $need[0].sha256; Add-Input $Ph.K1 'K1' $need[1].file $need[1].sha256 }
    'K2' { Add-Input $Ph.CLast 'C-last' $need[0].file $need[0].sha256; Add-Input $Ph.K0 'K0' $need[1].file $need[1].sha256; Add-Input $Ph.hero 'hero' $Hero $HeroSha }
    'D' { Add-Input $Ph.K2 'K2' $need[0].file $need[0].sha256 }
  }
  $built = Build-Body $stage $map $AddendumFile
  $runFile = New-Task -Label $Label -Stage $stage -Kind $kind -Built $built -Expected $price -After $after -Inputs $inputs -AttemptType $attemptType -Reason $reason
  $run = Read-Run $runFile
  'Задача создана: ' + $Label + ' taskId ' + $run.taskId + ' | ' + $run.model + ' | ожидается ' + $run.priceCr + ' кр | бюджет: ' + ($run.budget | ConvertTo-Json -Compress)
  'Запись: ' + $runFile
} finally { $env:KIE_API_KEY = $null }
