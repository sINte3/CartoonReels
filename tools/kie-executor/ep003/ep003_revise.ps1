# ep003_revise.ps1 — без расходов: записать ревизию 2 плана EP003 в СУЩЕСТВУЮЩИЙ журнал пакета.
# Проверяет входы коммита ревизии (plan.json, промпты, фильтр, начало), состояние пакета по записям ревизии 1
# (расход, счётчики, принятый K0, отклонённые K1, видео ещё нет), свежие цены по публичной таблице Kie и баланс.
# Журнал, записи задач и счётчики не меняются и не обнуляются: добавляются запись 'revision', 'balance' и копия нового промпта C в refs.
. (Join-Path $PSScriptRoot 'ep003_lib.ps1')
$Inv = [Globalization.CultureInfo]::InvariantCulture
$journal = Read-Journal
$act = @($journal | Where-Object { $_.type -eq 'activation' })
if ($act.Count -ne 1 -or $act[0].commit -ne $CommitRev1 -or $act[0].planSha256 -ne $PlanShaRev1) { throw 'В журнале нет активации ревизии 1 (коммит 025aad9) — ревизия 2 продолжает только этот пакет.' }
if (@($journal | Where-Object { $_.type -eq 'revision' -and $_.revision -eq $Revision }).Count) { throw ('Ревизия ' + $Revision + ' уже записана в журнал — продолжать по журналу.') }

# ---------- входы коммита ревизии ----------
if ((Get-Sha $PlanFile) -ne $PlanSha) { throw 'plan.json не совпал с коммитом ревизии 2 — export-inputs.ps1.' }
if ((Get-Sha $Hero) -ne $HeroSha) { throw 'Исходник героя не совпал по SHA-256.' }
if ((Get-Sha $Opening) -ne $OpeningSha -or (Get-Sha $OpeningLast) -ne $OpeningLastSha) { throw 'Готовое начало или его кадр 167 не совпали по SHA-256.' }
$fltFile = Join-Path $Dl 'assemble-with-audio.ffmpeg.txt'
if ((Get-Sha $fltFile) -ne $FilterSha) { throw 'Фильтр сборки не совпал с зафиксированным SHA-256.' }
$flt = @([IO.File]::ReadAllLines($fltFile))
if ($flt[0] -cne ('[0:v]' + $OpenChain + '[v0];') -or $flt[1] -cne ('[1:v]' + $CChain + '[v1];') -or $flt[2] -cne ('[2:v]' + $DChain + '[v2];')) { throw 'Цепочки видео в фильтре сборки не совпали с ep003_lib.ps1.' }
$plan = Get-Content -Raw -LiteralPath $PlanFile | ConvertFrom-Json -AsHashtable
$vt = @{}; foreach ($t in $plan.video_tasks) { $vt[$t.id] = $t }
$it = @{}; foreach ($t in $plan.image_tasks) { $it[$t.id] = $t }
$cIn = $vt.C.request_template.input; $dIn = $vt.D.request_template.input
$cKeys = (@($cIn.Keys) | Sort-Object) -join ','
if ([int]$plan.plan_revision.revision -ne $Revision -or $plan.plan_revision.previous_revision_commit -ne $CommitRev1 -or [double]$plan.plan_revision.credit_cap_including_spent -ne $Cap -or -not $plan.plan_revision.budget_not_reset -or
  [double]$plan.budget.authorized_cap -ne $Cap -or [int]$plan.target_master.frames -ne 384 -or -not $it.K1.excluded_from_graph -or
  $cKeys -ne 'aspect_ratio,duration,first_frame_url,generate_audio,prompt,resolution' -or $cIn.first_frame_url -ne $Ph.K0 -or [int]$cIn.duration -ne 5 -or $cIn.resolution -ne '720p' -or $cIn.aspect_ratio -ne '9:16' -or $cIn.generate_audio -ne $true -or
  ((@($vt.C.depends_on) -join ',') -ne 'accepted_K0') -or $dIn.Contains('last_frame_url') -or [int]$dIn.duration -ne 4 -or $dIn.first_frame_url -ne $Ph.K2) {
  throw 'plan.json не соответствует ревизии 2: C только first K0 / 5 с / без last_frame_url, K1 исключён, D 4 с first-only, предел 634, 384 кадра.'
}

# ---------- состояние пакета по записям ревизии 1 ----------
$sp = Get-Spend
if ($sp.open.Count) { throw ('Есть незавершённая или невыясненная отправка: ' + ($sp.open -join ', ') + '. Сначала выяснить.') }
Assert-Charges
$recs = @(Get-Records)
if ($sp.video -ne 0 -or @($recs | Where-Object { $_.stage -in 'C', 'K2', 'D' }).Count) { throw 'В журнале уже есть задачи C/K2/D — ревизия 2 записывается только до них.' }
$dec = @($journal | Where-Object { $_.type -in 'accept', 'reject' })
$k0 = @($dec | Where-Object { $_.stage -eq 'K0' }) | Select-Object -Last 1
if (-not $k0 -or $k0.type -ne 'accept' -or (Get-Sha $k0.file) -ne $k0.sha256) { throw 'Принятый K0 не найден или его файл изменился.' }
if (@($dec | Where-Object { $_.stage -eq 'K1' -and $_.type -eq 'accept' }).Count) { throw 'В журнале есть принятый K1 — ревизия 2 предполагает, что все K1 отклонены.' }
$k1Labels = @($recs | Where-Object { $_.stage -eq 'K1' } | ForEach-Object { $_.label })
foreach ($l in $k1Labels) { $d = @($dec | Where-Object { $_.label -eq $l }) | Select-Object -Last 1; if (-not $d -or $d.type -ne 'reject') { throw ('Попытка ' + $l + ' не отклонена в журнале.') } }
$remaining = [double]($Stages.C.price + $Stages.K2.price + $Stages.D.price)
$videoReserve = [double]([Math]::Max($Stages.C.price, $Stages.D.price))
if ($remaining -ne 381 -or [double]$Stages.C.after -ne 176 -or [double]$Stages.K2.after -ne 164 -or [double]$Stages.D.after -ne 0) { throw 'Остатки этапов в ep003_lib.ps1 не совпали с ревизией 2 (381 / 176 / 164 / 0).' }
if ($sp.actual + $remaining -gt $Cap) { throw ('Факт ' + $sp.actual + ' + обязательный остаток ' + $remaining + ' > ' + $Cap + '. Не продолжаю.') }
if ($sp.image + 1 -gt $MaxCreates.image) { throw ('Изображений уже ' + $sp.image + ' из ' + $MaxCreates.image + ' — на K2 не остаётся.') }
$maxTotal = $sp.actual + $remaining + $videoReserve

# ---------- свежие цены по публичной таблице (бесплатно, без ключа) ----------
function Get-PriceRows([string]$q) {
  $r = Invoke-RestMethod -Uri 'https://api.kie.ai/client/v1/model-pricing/page' -Method Post -ContentType 'application/json' -Body (@{ pageNum = 1; pageSize = 50; modelDescription = $q; interfaceType = '' } | ConvertTo-Json -Compress) -TimeoutSec 30 -SkipHttpErrorCheck
  if ($r.code -ne 200) { throw ('Таблица цен: код ' + $r.code + ' ' + $r.msg + '. Цена неизвестна — ревизию не записываю.') }
  @($r.data.records)
}
$nb = @(Get-PriceRows 'nano banana 2' | Where-Object { $_.modelDescription -eq 'Google nano banana 2, 2K' })
$sd = @(Get-PriceRows 'seedance-2' | Where-Object { $_.modelDescription -eq 'bytedance/seedance-2, 720p no video input' })
if ($nb.Count -ne 1 -or $sd.Count -ne 1) { throw 'В таблице цен не найдены строки «Google nano banana 2, 2K» и «bytedance/seedance-2, 720p no video input» — цена неизвестна.' }
if ([double]$nb[0].creditPrice -ne $ImagePrice -or $nb[0].creditUnit -ne 'per image' -or [double]$sd[0].creditPrice -ne $VideoPerSec -or $sd[0].creditUnit -ne 'per second') {
  throw ('Тариф изменился: nano-banana-2 2K = ' + $nb[0].creditPrice + ' ' + $nb[0].creditUnit + ', seedance-2 720p = ' + $sd[0].creditPrice + ' ' + $sd[0].creditUnit + '. Пересчитать $Stages и бюджет до продолжения.')
}

# ---------- баланс: хватает ли на обязательный остаток и сходится ли с записями ----------
Set-Key
try { $bal = Get-Balance } finally { $env:KIE_API_KEY = $null }
if ($bal -lt $remaining) { throw ('Баланс ' + $bal.ToString($Inv) + ' меньше обязательного остатка ' + $remaining + ' (C + K2 + D): не хватает ' + [Math]::Round($remaining - $bal, 2).ToString($Inv) + ' кр. Генерации не запускаю, счёт не пополняю.') }
[void](Assert-Balance $bal)

# ---------- новый промпт C в refs; K2 и D — прежние копии, сверка с plan.json ----------
$st = New-Stamp
foreach ($id in 'K2', 'D') {
  $t = if ($it.Contains($id)) { $it[$id] } else { $vt[$id] }
  $p = Join-Path $Refs ($Pfx + '_' + [IO.Path]::GetFileName($t.prompt_file))
  if ((Get-Sha $p) -ne $t.prompt_sha256) { throw ('Промпт ' + $p + ' не совпал с plan.json ревизии 2.') }
}
$src = Join-Path $Dl ($vt.C.prompt_file -replace '/', '__')
$dst = Join-Path $Refs ($Pfx + '_' + [IO.Path]::GetFileName($vt.C.prompt_file))
if (Test-Path -LiteralPath $dst) { throw ('Промпт ' + $dst + ' уже есть.') }
if ((Get-Sha $src) -ne $vt.C.prompt_sha256) { throw ('Промпт ' + $src + ' не совпал с plan.json.') }
[IO.File]::Copy($src, $dst)
if ((Get-Sha $dst) -ne $vt.C.prompt_sha256) { throw ('Копия ' + $dst + ' не совпала по SHA-256.') }
[IO.File]::WriteAllLines(($dst -replace '\.txt$', '.log.txt'), [string[]]@(
    ([IO.Path]::GetFileName($dst) + ' | промпт C (ревизия 2, только первый кадр K0) ' + $Episode + ' | ' + (Get-Item -LiteralPath $dst).Length + ' B | sha256=' + $vt.C.prompt_sha256 + ' | сохранено ' + $st),
    ('источник: git ' + $Commit + ':episodes/EP003/' + $vt.C.prompt_file + ' (https://github.com/sINte3/CartoonReels/blob/' + $Commit + '/episodes/EP003/' + $vt.C.prompt_file + '), SHA-256 совпал с plan.json того же коммита')
  ), $Utf8)

Add-Journal ([ordered]@{
    type        = 'revision'
    revision    = $Revision
    source      = 'Сообщение пользователя в чате Claude Code 09.11.2026: «Продолжай EP003 в существующем пакете до 634 кредитов, включая уже потраченные 48. Меняем C на режим только первого кадра: принятый K0, 5 секунд, 720p, 9:16, generate_audio=true. Поле last_frame_url полностью убрать. Отклонённые K1 оставить отклонёнными. Не помечать их принятыми ради обхода проверки. Новые K1 не создавать. Новый граф: принятый K0 → C → фактический конец C → K2 → D. […] Если K2 непригоден — остановись до D. Сохраняется один общий видеоповтор для C или D.»'
    commit      = $Commit
    previousCommit = $CommitRev1
    planSha256  = $PlanSha
    previousPlanSha256 = $PlanShaRev1
    instruction = [ordered]@{ path = 'episodes/EP003/CLAUDE_PRODUCE_FULL_RU.md'; url = 'https://github.com/sINte3/CartoonReels/blob/' + $Commit + '/episodes/EP003/CLAUDE_PRODUCE_FULL_RU.md'; sha256 = (Get-Sha (Join-Path $Dl 'CLAUDE_PRODUCE_FULL_RU.md')) }
    graph       = 'принятый K0 → C (только first K0, 5 с, без last_frame_url) → кадр 119 C → K2 → D (только first K2, 4 с)'
    excluded    = [ordered]@{ K1 = 'отклонён трижды (' + ($k1Labels -join ', ') + '), новые K1 не создаются, принимать нельзя'; K0 = 'принят в ревизии 1 (' + [IO.Path]::GetFileName($k0.file) + '), новых K0 нет' }
    acceptedK0  = [ordered]@{ file = $k0.file; sha256 = $k0.sha256; taskId = $k0.taskId }
    cPrompt     = [ordered]@{ file = $dst; sha256 = $vt.C.prompt_sha256; superseded = 'prompts/C-solo-lift.prompt.en.txt (first+last) не используется' }
    preserved   = [ordered]@{ spentActual = $sp.actual; imageCreates = $sp.image; imageRetries = $sp.imageRetry; videoCreates = $sp.video; videoRetries = $sp.videoRetry; budgetReset = $false }
    remaining   = [ordered]@{ mandatory = $remaining; formula = 'C 205 + K2 12 + D 164'; base = $sp.actual + $remaining; sharedVideoRetryMax = $videoReserve; maxTotal = $maxTotal; cap = $Cap; imageCreatesLeft = $MaxCreates.image - $sp.image; imageRetriesLeft = $MaxRetries.image - $sp.imageRetry; videoCreatesLeft = $MaxCreates.video - $sp.video; videoRetriesLeft = $MaxRetries.video - $sp.videoRetry; remainingMandatoryAfter = [ordered]@{ C = 176; K2 = 164; D = 0 }; stopBeforeDIfK2Unusable = $true }
    prices      = [ordered]@{
      checkedAt      = (Now)
      source         = 'POST https://api.kie.ai/client/v1/model-pricing/page (данные таблицы kie.ai/pricing)'
      nanoBanana2_2K = '«' + $nb[0].modelDescription + '» — ' + $nb[0].creditPrice + ' кр ' + $nb[0].creditUnit + ' ($' + $nb[0].usdPrice + ')'
      seedance2_720p = '«' + $sd[0].modelDescription + '» — ' + $sd[0].creditPrice + ' кр ' + $sd[0].creditUnit + ' ($' + $sd[0].usdPrice + '); first-only — картинка, это строка без видео-входа; C 5 с = 205, D 4 с = 164'
    }
    balance     = $bal
  })
'Ревизия ' + $Revision + ' записана: коммит ' + $Commit.Substring(0, 7) + ', plan ' + $PlanSha.Substring(0, 12)
'Сохранено из ревизии 1: факт ' + $sp.actual + ' кр, изображений ' + $sp.image + ' (повторов ' + $sp.imageRetry + '), видео ' + $sp.video + ' (повторов ' + $sp.videoRetry + ')'
'Цены: nano-banana-2 2K ' + $nb[0].creditPrice + ' кр, seedance-2 720p ' + $sd[0].creditPrice + ' кр/с; обязательный остаток ' + $remaining + ', база ' + ($sp.actual + $remaining) + ', максимум с видеоповтором ' + $maxTotal + ' ≤ ' + $Cap
'Баланс: ' + $bal.ToString($Inv) + ' кр'
'Промпт C: ' + $dst
