# v3_lib.ps1 — общий код пакета EP001 V3 «Чисто. Почти.» (Kie AI: nano-banana-2 и bytedance/seedance-2).
# Логика загрузки, createTask, опроса и скачивания — блоки 1–3 карточки models/seedance-2.0.md,
# обобщённые на картинки (image_input) и на first+last frame со звуком. Подключать через dot-source.
# Ключ берётся из .env в переменную окружения процесса; в вывод, журнал и записи не попадает.
# Архив исполнения 08.11.2026. После переноса в репозиторий изменены только пути: $Dl, .env и файл фильтра с усилением (v3_assemble). См. tools/kie-executor/README.md.
$ErrorActionPreference = 'Stop'
$Gen      = if ($env:V3_TEST_GEN) { $env:V3_TEST_GEN } else { 'E:\Generations' }
$Refs     = Join-Path $Gen 'refs'
$Pfx      = 'CartoonReels_EP001_V3'
$Cap      = 600
$Commit   = '8e3ac3e99040905cca95d6893553e8ec4332a6e7'
$Dl       = if ($env:KIE_EXEC_INPUTS) { $env:KIE_EXEC_INPUTS } else { Join-Path $PSScriptRoot 'inputs' }   # файлы коммита $Commit, их создаёт export-inputs.ps1 (08.11.2026 здесь была временная папка сессии)
$PlanFile = Join-Path $Dl 'plan.json'
$PlanSha  = 'f3eb831abe39c4a37cfdc0421b192d5316f8aed83b101b82f6461be25dcd7496'
$Hero     = Join-Path $Refs 'hero-3d-keyframe.png'
$HeroSha  = '97c4c09087da7d9523496e2cbf0e3be2dff2b5a374097ca511aba3b80915fdde'
$PriceCr  = @{ image = 12; video = 164 }        # страницы моделей Kie, 08.11.2026 11:42: NB2 2K = 12; Seedance 2 720p без видео-входа = 41 кр/с × 4 с
$MaxCreates = @{ image = 5; video = 3 }
$MaxRetries = @{ image = 2; video = 1 }
$Utf8     = [Text.UTF8Encoding]::new($false)
# after = ожидаемая цена обязательных этапов, которые останутся после этого: K0 → K1+A+K2+B и т.д.
$Stages = [ordered]@{
  K0 = @{ kind = 'image'; after = 352 }
  K1 = @{ kind = 'image'; after = 340 }
  A  = @{ kind = 'video'; after = 176 }
  K2 = @{ kind = 'image'; after = 164 }
  B  = @{ kind = 'video'; after = 0 }
}
$Ph = @{
  hero  = '__UPLOADED_ORIGINAL_CHARACTER_REFERENCE__'
  K0    = '__UPLOADED_APPROVED_K0__'
  K1    = '__UPLOADED_APPROVED_K1__'
  K2    = '__UPLOADED_APPROVED_K2__'
  ALast = '__UPLOADED_ACTUAL_ACCEPTED_A_LAST_FRAME__'
}

function Now { (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz') }
function New-Stamp { Get-Date -Format 'yyyyMMdd-HHmmss' }
function Get-Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }

function Set-Key {
  if ($env:V3_TEST_GEN) { $env:KIE_API_KEY = 'FAKE-KEY-dryrun-0000'; return }
  $env:KIE_API_KEY = ((Get-Content (Join-Path $HOME '.env') | Where-Object { $_ -match '^\s*KIE_API_KEY\s*=' }) -replace '^[^=]*=', '').Trim().Trim('"').Trim("'")
  if (-not $env:KIE_API_KEY) { throw 'KIE_API_KEY не найден в .env' }
}
function Get-Hdr { @{ Authorization = "Bearer $env:KIE_API_KEY" } }

# ---------- журнал и записи задач ----------
function Get-JournalPath {
  $j = @(Get-ChildItem -LiteralPath $Gen -Filter ($Pfx + '_journal_*.jsonl') -File)
  if ($j.Count -ne 1) { throw ('Журнал пакета: найдено ' + $j.Count + ' файлов ' + $Pfx + '_journal_*.jsonl, нужен ровно один.') }
  $j[0].FullName
}
function Add-Journal([System.Collections.IDictionary]$e) {
  $o = [ordered]@{ at = (Now) }
  foreach ($k in $e.Keys) { $o[$k] = $e[$k] }
  [IO.File]::AppendAllText((Get-JournalPath), (($o | ConvertTo-Json -Depth 12 -Compress) + "`n"), $Utf8)
}
function Read-Journal {
  @(Get-Content -LiteralPath (Get-JournalPath) -Encoding utf8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
}
function Save-Run([string]$path, $rec) {
  $j = $rec | ConvertTo-Json -Depth 12
  [IO.File]::WriteAllText($path, $j, $Utf8)
  if ([IO.File]::ReadAllText($path) -cne $j) { throw ('Не удалось записать ' + $path) }
}
function Read-Run([string]$path) { Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -AsHashtable }
function Get-Records {
  @(Get-ChildItem -LiteralPath $Gen -Filter ($Pfx + '_*.task.json') -File | Sort-Object Name | ForEach-Object {
      $r = Read-Run $_.FullName; $r['_path'] = $_.FullName; $r })
}
function Get-RecordByLabel([string]$label) {
  $m = @(Get-Records | Where-Object { $_.label -eq $label })
  if ($m.Count -ne 1) { throw ('Запись этапа ' + $label + ': найдено ' + $m.Count + ', нужна одна.') }
  $m[0]
}
# Фактический расход по записям; всё незавершённое/невыясненное считается по ожидаемой цене, не нулём.
function Get-Spend {
  $o = [ordered]@{ actual = 0.0; pending = 0.0; image = 0; video = 0; imageRetry = 0; videoRetry = 0; open = @() }
  foreach ($r in Get-Records) {
    $o[$r.kind] = $o[$r.kind] + 1
    if ($r.attemptType -eq 'retry') { $o[$r.kind + 'Retry'] = $o[$r.kind + 'Retry'] + 1 }
    if ($r.status -in 'success', 'fail' -and $null -ne $r.creditsConsumed) { $o.actual += [double]$r.creditsConsumed }
    elseif ($r.status -ne 'rejected') { $o.pending += [double]$r.priceCr; $o.open += $r.label }
  }
  $o
}
function Assert-Charges {
  $acks = @(Read-Journal | Where-Object { $_.type -eq 'charge-ack' } | ForEach-Object { $_.label })
  foreach ($r in Get-Records) {
    $bad = ($r.status -eq 'success' -and [double]$r.creditsConsumed -ne [double]$r.priceCr) -or ($r.status -eq 'fail' -and [double]$r.creditsConsumed -ne 0)
    if ($bad -and $r.label -notin $acks) { throw ('Списание этапа ' + $r.label + ': ' + $r.creditsConsumed + ' кр при ожидании ' + $(if ($r.status -eq 'fail') { 0 } else { $r.priceCr }) + '. Новые расходы остановлены до разбора.') }
  }
}
function Get-Balance {
  $c = Invoke-RestMethod -Uri 'https://api.kie.ai/api/v1/chat/credit' -Headers (Get-Hdr) -TimeoutSec 30 -SkipHttpErrorCheck
  if ($c.code -ne 200) { throw ('Баланс: код ' + $c.code + ' ' + $c.msg) }
  [double]$c.data
}
function Assert-Balance([double]$bal) {
  $act = @(Read-Journal | Where-Object { $_.type -eq 'activation' })[0]
  $start = [double]$act.balanceStart
  $sp = Get-Spend
  $diff = [Math]::Round($start - $bal, 2)
  if ($sp.open.Count -eq 0) { $ok = [Math]::Abs($diff - $sp.actual) -lt 0.011 }
  else { $ok = ($diff -ge $sp.actual - 0.011) -and ($diff -le $sp.actual + $sp.pending + 0.011) }
  Add-Journal ([ordered]@{ type = 'balance'; balance = $bal; spentByBalance = $diff; actualByTasks = $sp.actual; pending = $sp.pending; consistent = $ok })
  if (-not $ok) { throw ('Баланс не сходится: в начале ' + $start + ', сейчас ' + $bal + ' (−' + $diff + '), по задачам ' + $sp.actual + ' (+ неясное ' + $sp.pending + '). Новые расходы остановлены.') }
}
# Все запреты до любой загрузки и отправки. Повторяется непосредственно перед createTask.
function Assert-CanCreate([string]$label, [string]$kind, [string]$attemptType, [double]$expected, [double]$after) {
  if (@(Get-Records | Where-Object { $_.label -eq $label }).Count) { throw ('Запись этапа ' + $label + ' уже есть — повторная отправка запрещена.') }
  $sp = Get-Spend
  if ($sp.open.Count) { throw ('Есть незавершённая или невыясненная отправка: ' + ($sp.open -join ', ') + '. Новые платные действия остановлены до выяснения.') }
  if ($sp[$kind] -ge $MaxCreates[$kind]) { throw ('Лимит отправок (' + $kind + ' ' + $MaxCreates[$kind] + ') исчерпан.') }
  if ($attemptType -eq 'retry' -and $sp[$kind + 'Retry'] -ge $MaxRetries[$kind]) { throw ('Резерв исправлений (' + $kind + ' ' + $MaxRetries[$kind] + ') исчерпан.') }
  Assert-Charges
  $projected = $sp.actual + $sp.pending + $expected + $after
  if ($projected -gt $Cap) { throw ('Бюджет: факт ' + $sp.actual + ' + неясное ' + $sp.pending + ' + этот этап ' + $expected + ' + оставшиеся обязательные ' + $after + ' = ' + $projected + ' > ' + $Cap + '. Не отправляю.') }
  [ordered]@{ actualBefore = $sp.actual; pendingBefore = $sp.pending; expected = $expected; remainingMandatoryAfter = $after; projectedMax = $projected; cap = $Cap }
}

# ---------- загрузка входного файла (бесплатно, живёт 24 ч) с проверкой обратным скачиванием ----------
function Send-Upload([string]$file, [string]$sha) {
  if ((Get-Sha $file) -ne $sha) { throw ('Файл ' + $file + ' не совпал по SHA-256 — загрузка не выполняется.') }
  $st = New-Stamp
  $upName = [IO.Path]::GetFileNameWithoutExtension($file) + '_up' + $st + '.png'
  $raw = curl.exe -sS --max-time 180 -X POST 'https://kieai.redpandaai.co/api/file-stream-upload' -H "Authorization: Bearer $env:KIE_API_KEY" -F "file=@$file;type=image/png" -F 'uploadPath=cartoonreels/ep001-v3' -F "fileName=$upName"
  if ($LASTEXITCODE -ne 0) { throw ('Загрузка ' + $file + ' не удалась (curl ' + $LASTEXITCODE + '). createTask не отправлен.') }
  try { $up = ($raw -join "`n") | ConvertFrom-Json } catch { throw ('Загрузка ' + $file + ': ответ не JSON. createTask не отправлен.') }
  if (-not ($up.success -eq $true -and $up.code -eq 200)) { throw ('Загрузка ' + $file + ' отклонена: ' + $up.code + ' ' + $up.msg + '. createTask не отправлен.') }
  $url = [string]$up.data.downloadUrl; $u = $null
  if (-not ([Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$u) -and $u.Scheme -eq 'https')) { throw ('Загрузка ' + $file + ': downloadUrl пустой или не https. createTask не отправлен.') }
  if ([long]$up.data.fileSize -ne (Get-Item -LiteralPath $file).Length -or $up.data.mimeType -ne 'image/png') { throw ('Загрузка ' + $file + ': не совпали размер или тип (' + $up.data.fileSize + ' B, ' + $up.data.mimeType + '). createTask не отправлен.') }
  $chk = Join-Path ([IO.Path]::GetTempPath()) ('v3_upcheck_' + $st + '_' + [IO.Path]::GetFileName($file))
  try { Invoke-WebRequest -Uri $url -OutFile $chk -TimeoutSec 180 | Out-Null } catch { throw ('downloadUrl для ' + $file + ' не открывается: ' + $_.Exception.Message + '. createTask не отправлен.') }
  $same = (Get-Sha $chk) -eq $sha; [IO.File]::Delete($chk)
  if (-not $same) { throw ('По downloadUrl лежит не тот файл (' + $file + '). createTask не отправлен.') }
  Add-Journal ([ordered]@{ type = 'upload'; file = $file; sha256 = $sha; bytes = (Get-Item -LiteralPath $file).Length; fileName = $upName; url = $url; verified = 'success+code200, https, size, mime, sha256 round-trip' })
  $url
}

# ---------- тело запроса строго из шаблона plan.json зафиксированного коммита ----------
function Build-Body([string]$planId, [System.Collections.IDictionary]$map, [string]$addendumFile = '') {
  if ((Get-Sha $PlanFile) -ne $PlanSha) { throw 'plan.json не совпал с зафиксированным коммитом.' }
  $plan = Get-Content -Raw -LiteralPath $PlanFile | ConvertFrom-Json -AsHashtable
  $t = @(@($plan.image_tasks) + @($plan.video_tasks) | Where-Object { $_.id -eq $planId })
  if ($t.Count -ne 1) { throw ('Нет задачи ' + $planId + ' в plan.json') }
  $t = $t[0]; $tpl = $t.request_template
  $in = [ordered]@{}
  foreach ($k in $tpl.input.Keys) {
    $v = $tpl.input[$k]
    if ($k -eq 'image_input') { $in[$k] = @(foreach ($x in $v) { if ($map.ContainsKey($x)) { $map[$x] } else { throw ('Нет проверенного URL для ' + $x) } }) }
    elseif ($k -in 'first_frame_url', 'last_frame_url') { if ($map.ContainsKey($v)) { $in[$k] = $map[$v] } else { throw ('Нет проверенного URL для ' + $v) } }
    else { $in[$k] = $v }
  }
  $body = [ordered]@{ model = $tpl.model; input = $in }
  $json = $body | ConvertTo-Json -Depth 10
  if ($json -match '__UPLOADED_') { throw 'В теле запроса остались заглушки.' }
  # промпт: файл в refs совпадает с plan.json по SHA-256, текст тела = файл без хвостового перевода строки
  $pf = Join-Path $Refs ($Pfx + '_' + [IO.Path]::GetFileName($t.prompt_file))
  if ((Get-Sha $pf) -ne $t.prompt_sha256) { throw ('Промпт ' + $pf + ' не совпал по SHA-256 с plan.json.') }
  if ([IO.File]::ReadAllText($pf).TrimEnd("`r", "`n") -cne $in.prompt) { throw ('Промпт в теле не равен файлу ' + $pf) }
  # адресная правка (только для повтора): базовый промпт плана без изменений + абзац исправления из отдельного файла
  $add = $null
  if ($addendumFile) {
    $addText = [IO.File]::ReadAllText($addendumFile).TrimEnd("`r", "`n")
    if ($addText.Length -lt 20 -or @($addText.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count) { throw ('Файл правки ' + $addendumFile + ' пуст или не ASCII.') }
    $in.prompt = $in.prompt + "`n" + $addText
    if ($in.prompt.Length -gt 10000) { throw 'Промпт с правкой слишком длинный.' }
    $add = [ordered]@{ file = $addendumFile; sha256 = (Get-Sha $addendumFile); text = $addText }
    $json = $body | ConvertTo-Json -Depth 10
  }
  $keys = (@($in.Keys) | Sort-Object) -join ','
  if ($tpl.model -eq 'nano-banana-2') {
    if ($keys -ne 'aspect_ratio,image_input,output_format,prompt,resolution' -or $in.aspect_ratio -ne '9:16' -or $in.resolution -ne '2K' -or $in.output_format -ne 'png' -or @($in.image_input).Count -lt 1 -or @($in.image_input).Count -gt 10) { throw ('Тело ' + $planId + ' не соответствует nano-banana-2 2K 9:16 png: ' + $keys) }
  } elseif ($tpl.model -eq 'bytedance/seedance-2') {
    if ($keys -ne 'aspect_ratio,duration,first_frame_url,generate_audio,last_frame_url,prompt,resolution' -or -not ($in.duration -is [long] -or $in.duration -is [int]) -or $in.duration -ne 4 -or $in.resolution -ne '720p' -or $in.aspect_ratio -ne '9:16' -or $in.generate_audio -isnot [bool] -or -not $in.generate_audio) { throw ('Тело ' + $planId + ' не соответствует seedance-2 4 с 720p 9:16 со звуком: ' + $keys) }
  } else { throw ('Неожиданная модель ' + $tpl.model) }
  [ordered]@{ body = $body; json = $json; prompt_file = $pf; prompt_sha256 = $t.prompt_sha256; addendum = $add }
}

# ---------- одна отправка createTask с записью до и после ----------
function New-Task([string]$Label, [string]$Stage, [string]$Kind, $Built, [double]$Expected, [double]$After, $Inputs, [string]$AttemptType, [string]$Reason) {
  $budget = Assert-CanCreate $Label $Kind $AttemptType $Expected $After
  $runFile = Join-Path $Gen ($Pfx + '_' + $Label + '_' + (New-Stamp) + '.task.json')
  if (Test-Path -LiteralPath $runFile) { throw ('Запись ' + $runFile + ' уже есть — не перезаписывать.') }
  $run = [ordered]@{ label = $Label; stage = $Stage; kind = $Kind; attemptType = $AttemptType; reason = $Reason; status = 'sending'; taskId = $null
    model = $Built.body.model; input = $Built.body.input; priceCr = $Expected; budget = $budget; inputs = $Inputs
    promptFile = $Built.prompt_file; promptSha256 = $Built.prompt_sha256; promptAddendum = $Built.addendum; planCommit = $Commit; sentAt = (Now) }
  Save-Run $runFile $run
  Add-Journal ([ordered]@{ type = 'intent'; label = $Label; stage = $Stage; kind = $Kind; attemptType = $AttemptType; reason = $Reason; promptAddendum = $Built.addendum; model = $Built.body.model; expectedCr = $Expected; budget = $budget; record = [IO.Path]::GetFileName($runFile) })
  $http = 0
  try {
    $r = Invoke-RestMethod -Uri 'https://api.kie.ai/api/v1/jobs/createTask' -Method Post -Headers (Get-Hdr) -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($Built.json)) -TimeoutSec 120 -SkipHttpErrorCheck -StatusCodeVariable http
  } catch {
    $run.status = 'unknown'; $run.error = $_.Exception.Message; Save-Run $runFile $run
    Add-Journal ([ordered]@{ type = 'create-unknown'; label = $Label; error = $_.Exception.Message })
    throw ('createTask без ответа (' + $_.Exception.Message + '). Задача могла создаться: НЕ повторять, сверить баланс и kie.ai/logs.')
  }
  $code = if ($null -ne $r.code) { [int]$r.code } else { [int]$http }
  $taskId = [string]$r.data.taskId
  if ($code -eq 200 -and $taskId -match '^[A-Za-z0-9_.:-]{6,128}$') {
    $run.status = 'created'; $run.taskId = $taskId; $run.createdAt = (Now)
    try { Save-Run $runFile $run } catch { throw ('Задача СОЗДАНА (' + $taskId + '), но запись на диск не удалась: ' + $_.Exception.Message + '. Новую задачу не создавать.') }
    Add-Journal ([ordered]@{ type = 'created'; label = $Label; taskId = $taskId; record = [IO.Path]::GetFileName($runFile) })
    return $runFile
  } elseif ($code -in 200, 500, 501, 502, 503, 504) {
    $run.status = 'unknown'; $run.code = $code; $run.msg = [string]$r.msg; $run.rawTaskId = $taskId; Save-Run $runFile $run
    Add-Journal ([ordered]@{ type = 'create-unknown'; label = $Label; code = $code; msg = [string]$r.msg })
    throw ('createTask: код ' + $code + ', taskId "' + $taskId + '". Задача могла создаться: НЕ повторять, сверить kie.ai/logs.')
  } else {
    $run.status = 'rejected'; $run.code = $code; $run.msg = [string]$r.msg; Save-Run $runFile $run
    Add-Journal ([ordered]@{ type = 'create-rejected'; label = $Label; code = $code; msg = [string]$r.msg })
    throw ('createTask отклонён: ' + $code + ' ' + $r.msg + '. Задача не создана. Сам не повторять.')
  }
}

# ---------- опрос по сохранённому taskId (бесплатно, можно повторять) ----------
function Wait-Task([string]$runFile, [double]$minutes = 8.5) {
  $run = Read-Run $runFile
  if ($run.status -in 'success', 'fail') { return $run }
  $taskId = [string]$run.taskId
  if ($taskId -notmatch '^[A-Za-z0-9_.:-]{6,128}$') { throw ('В ' + $runFile + ' нет корректного taskId (status = ' + $run.status + '). Опрашивать нечего; новую задачу не создавать.') }
  $h = Get-Hdr
  $deadline = (Get-Date).AddMinutes($minutes); $wait = 3; $state = $null; $fails = 0; $issue = $null; $s = $null; $code = 0
  while ($true) {
    Start-Sleep -Seconds $wait; $wait = [Math]::Min($wait * 2, 20)
    $s = $null; $http = 0
    try {
      $s = Invoke-RestMethod -Uri ('https://api.kie.ai/api/v1/jobs/recordInfo?taskId=' + [Uri]::EscapeDataString($taskId)) -Headers $h -TimeoutSec 60 -SkipHttpErrorCheck -StatusCodeVariable http
      $code = if ($null -ne $s.code) { [int]$s.code } else { [int]$http }
    } catch { $code = 0; $issue = 'нет ответа: ' + $_.Exception.Message }
    if ($code -eq 200) {
      $fails = 0; $state = [string]$s.data.state
      if ($state -in 'success', 'fail') { break }
      if ($state -notin 'waiting', 'queuing', 'generating') { throw ('recordInfo: неизвестный state "' + $state + '" у ' + $taskId + '. Новую задачу не создавать.') }
    }
    elseif ($code -in 401, 403) { throw ('recordInfo: ошибка авторизации (' + $code + ' ' + $s.msg + ') — это не «задача идёт». Новую задачу не создавать.') }
    elseif ($code -in 400, 404, 422) { throw ('recordInfo: ошибка параметров (' + $code + ' ' + $s.msg + ') для ' + $taskId + '. Новую задачу не создавать.') }
    elseif ($code -in 0, 408, 429, 433, 455, 500, 502, 503, 504) { $fails++; if ($code) { $issue = 'код ' + $code + ' ' + $s.msg } }
    else { throw ('recordInfo: неожиданный код ' + $code + ' ' + $s.msg + ' для ' + $taskId + '. Новую задачу не создавать.') }
    if ((Get-Date) -gt $deadline) { break }
  }
  $run.lastCheckedAt = (Now); $run.state = $state
  if ($code -eq 200 -and $state -eq 'success') {
    $res = [string]$s.data.resultJson | ConvertFrom-Json
    $run.status = 'success'; $run.resultUrls = @($res.resultUrls); $run.resultJson = [string]$s.data.resultJson
    $run.creditsConsumed = $s.data.creditsConsumed; $run.costTime = $s.data.costTime; $run.completedAt = (Now)
    Save-Run $runFile $run
    Add-Journal ([ordered]@{ type = 'result'; label = $run.label; taskId = $taskId; state = 'success'; creditsConsumed = $s.data.creditsConsumed; expectedCr = $run.priceCr; costTime = $s.data.costTime })
    if (-not @($res.resultUrls)[0]) { throw ('success без resultUrls у ' + $taskId + '. Новую задачу не создавать.') }
  } elseif ($code -eq 200 -and $state -eq 'fail') {
    $run.status = 'fail'; $run.failCode = $s.data.failCode; $run.failMsg = $s.data.failMsg; $run.creditsConsumed = $s.data.creditsConsumed; $run.completedAt = (Now)
    Save-Run $runFile $run
    Add-Journal ([ordered]@{ type = 'result'; label = $run.label; taskId = $taskId; state = 'fail'; failCode = $s.data.failCode; failMsg = $s.data.failMsg; creditsConsumed = $s.data.creditsConsumed })
  } else { Save-Run $runFile $run }
  $run['_issue'] = $issue; $run['_fails'] = $fails
  $run
}

# ---------- скачивание результата и техническая проверка ----------
function Save-Result([string]$runFile) {
  $run = Read-Run $runFile
  $url = [string]@($run.resultUrls)[0]
  if ($run.status -ne 'success' -or -not $url) { throw ('В ' + $runFile + ' нет готового результата (status = ' + $run.status + ').') }
  $base = $runFile -replace '\.task\.json$', ''
  foreach ($e in 'png', 'jpg', 'mp4') { if (Test-Path -LiteralPath ($base + '.' + $e)) { throw ('Результат ' + $base + '.' + $e + ' уже сохранён — не перезаписываю.') } }
  $part = $base + '.part'
  try { Invoke-WebRequest -Uri $url -OutFile $part -TimeoutSec 600 | Out-Null }
  catch {
    $d = Invoke-RestMethod -Uri 'https://api.kie.ai/api/v1/common/download-url' -Method Post -Headers (Get-Hdr) -ContentType 'application/json' -Body (@{ url = $url } | ConvertTo-Json) -TimeoutSec 60 -SkipHttpErrorCheck
    if ($d.code -ne 200 -or -not $d.data) { throw ('Скачивание не удалось (' + $d.code + ' ' + $d.msg + '). Задача ' + $run.taskId + ' цела: повторить позже, новую не создавать.') }
    Invoke-WebRequest -Uri ([string]$d.data) -OutFile $part -TimeoutSec 600 | Out-Null
  }
  $b = [IO.File]::ReadAllBytes($part)
  $ext = if ($b.Length -gt 8 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { 'png' } elseif ($b.Length -gt 3 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8) { 'jpg' } elseif ($b.Length -gt 12 -and [Text.Encoding]::ASCII.GetString($b, 4, 4) -eq 'ftyp') { 'mp4' } else { 'bin' }
  $out = $base + '.' + $ext
  [IO.File]::Move($part, $out)
  $err = (ffmpeg -v error -i $out -f null - 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or $err) { throw ('Файл ' + $out + ' не декодируется: ' + $err + '. Задача ' + $run.taskId + ' цела: скачать заново, новую не создавать.') }
  $p = (ffprobe -v error -show_entries 'stream=index,codec_type,codec_name,width,height,r_frame_rate,nb_frames,sample_rate,channels,duration:format=duration' -of json $out | Out-String) | ConvertFrom-Json
  $v = @($p.streams | Where-Object codec_type -eq 'video')[0]
  $a = @($p.streams | Where-Object codec_type -eq 'audio')[0]
  $info = [ordered]@{ file = [IO.Path]::GetFileName($out); bytes = (Get-Item -LiteralPath $out).Length; sha256 = (Get-Sha $out); format = $ext; width = $v.width; height = $v.height; vcodec = $v.codec_name }
  if ($ext -eq 'mp4') {
    $info.duration_s = [double]$p.format.duration; $info.fps = $v.r_frame_rate; $info.frames = $v.nb_frames
    $info.audio = [bool]$a
    if ($a) {
      $vd = (ffmpeg -hide_banner -nostats -i $out -map 0:a:0 -af volumedetect -f null - 2>&1 | Out-String)
      $info.acodec = $a.codec_name; $info.sample_rate = $a.sample_rate; $info.channels = $a.channels; $info.audio_duration_s = $a.duration
      $info.mean_volume_db = if ($vd -match 'mean_volume:\s*(-?[\d.]+|-inf)') { $Matches[1] }; $info.max_volume_db = if ($vd -match 'max_volume:\s*(-?[\d.]+|-inf)') { $Matches[1] }
    }
  }
  [IO.File]::WriteAllText($base + '.result.json', [string]$run.resultJson, $Utf8)
  $name = [IO.Path]::GetFileName($base)
  [IO.File]::WriteAllLines($base + '.log.txt', [string[]]@(
      ($name + ' | kie ' + $run.model + ' | taskId=' + $run.taskId + ' | этап ' + $run.label + ' (' + $run.attemptType + ') | ожидалось ' + $run.priceCr + ' кр | creditsConsumed=' + $run.creditsConsumed + ' | costTime=' + $run.costTime + ' с | сохранено ' + (New-Stamp)),
      ('пакет EP001 V3, лимит 600 кр; commit ' + $Commit + '; промпт ' + $run.promptFile + ' sha256=' + $run.promptSha256),
      ('input: ' + ($run.input | ConvertTo-Json -Compress -Depth 6)),
      ('входные файлы: ' + ($run.inputs | ConvertTo-Json -Compress -Depth 6)),
      ($name + '.' + $ext + '  ' + ($info | ConvertTo-Json -Compress)),
      ('сырой результат: ' + $name + '.result.json | запись задачи: ' + $name + '.task.json | журнал пакета: ' + [IO.Path]::GetFileName((Get-JournalPath)))
    ), $Utf8)
  Add-Journal ([ordered]@{ type = 'saved'; label = $run.label; taskId = $run.taskId; result = $info })
  $info
}
