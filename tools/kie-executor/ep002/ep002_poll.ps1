# ep002_poll.ps1 -Label <этап> [-Minutes 8.5] — бесплатный опрос по сохранённому taskId. Новую задачу не создаёт.
param([Parameter(Mandatory)][string]$Label, [double]$Minutes = 8.5)
. (Join-Path $PSScriptRoot 'ep002_lib.ps1')
Set-Key
try {
  $rec = Get-RecordByLabel $Label
  $run = Wait-Task $rec._path $Minutes
  if ($run.status -eq 'success') { 'Готово: ' + $Label + ' taskId ' + $run.taskId + ', creditsConsumed = ' + $run.creditsConsumed + ' (ожидалось ' + $run.priceCr + '), costTime ' + $run.costTime + ' с' }
  elseif ($run.status -eq 'fail') { 'УПАЛА: ' + $Label + ' taskId ' + $run.taskId + ': ' + $run.failCode + ' ' + $run.failMsg + ', creditsConsumed = ' + $run.creditsConsumed }
  else { 'Ещё идёт: ' + $Label + ' taskId ' + $run.taskId + ', state = ' + $run.state + $(if ($run._fails) { ', сбоев опроса подряд ' + $run._fails + ': ' + $run._issue }) }
} finally { $env:KIE_API_KEY = $null }
