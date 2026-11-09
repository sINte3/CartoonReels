# ep003_decide.ps1 -Label <этап> -Decision accept|reject -Reason '...' — записать оценку результата в журнал пакета.
param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][ValidateSet('accept', 'reject')][string]$Decision, [Parameter(Mandatory)][string]$Reason)
. (Join-Path $PSScriptRoot 'ep003_lib.ps1')
$rec = Get-RecordByLabel $Label
$base = $rec._path -replace '\.task\.json$', ''
$files = @(foreach ($e in 'png', 'jpg', 'mp4') { if (Test-Path -LiteralPath ($base + '.' + $e)) { $base + '.' + $e } })
if ($Decision -eq 'accept' -and ($rec.status -ne 'success' -or $files.Count -ne 1)) { throw ('Принять можно только сохранённый успешный результат: status = ' + $rec.status + ', файлов ' + $files.Count) }
if ($rec.status -notin 'success', 'fail') { throw ('Задача ' + $Label + ' ещё не завершена (status = ' + $rec.status + ').') }
$e = [ordered]@{ type = $Decision; stage = $rec.stage; label = $Label; taskId = $rec.taskId; file = $(if ($files.Count) { $files[0] }); sha256 = $(if ($files.Count) { Get-Sha $files[0] }); reason = $Reason }
Add-Journal $e
$Decision + ' ' + $Label + ': ' + $Reason
