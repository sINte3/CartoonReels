# ep003_save.ps1 -Label <этап> — скачать результат по сохранённой записи, проверить, записать лог. Сорвалось — запустить снова.
param([Parameter(Mandatory)][string]$Label)
. (Join-Path $PSScriptRoot 'ep003_lib.ps1')
Set-Key
try {
  $rec = Get-RecordByLabel $Label
  $info = Save-Result $rec._path
  'Сохранено: ' + ($info | ConvertTo-Json -Compress)
} finally { $env:KIE_API_KEY = $null }
