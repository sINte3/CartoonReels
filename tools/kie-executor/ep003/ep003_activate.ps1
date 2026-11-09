# ep003_activate.ps1 — без расходов: проверка входов пакета EP003 (план, фильтр, герой, готовое начало и его кадр 167),
# свежая проверка цен по публичной таблице Kie, стартовый баланс, копии промптов в refs и запись пакетного разрешения в журнал.
# При недостатке средств на базовый пакет — остановка до любой генерации с указанием недостающей суммы.
. (Join-Path $PSScriptRoot 'ep003_lib.ps1')
$Inv = [Globalization.CultureInfo]::InvariantCulture
if (@(Get-ChildItem -LiteralPath $Gen -Filter ($Pfx + '_journal_*.jsonl') -File).Count) { throw 'Журнал пакета уже существует — повторная активация не нужна, продолжать по журналу.' }
if (@(Get-ChildItem -LiteralPath $Gen -Filter ($Pfx + '_*.task.json') -File).Count) { throw 'Записи задач EP003 уже есть без журнала — разобраться до активации.' }
if ((Get-Sha $PlanFile) -ne $PlanSha) { throw 'plan.json не совпал с зафиксированным коммитом.' }
if ((Get-Sha $Hero) -ne $HeroSha) { throw 'Исходник героя не совпал по SHA-256.' }
$fltFile = Join-Path $Dl 'assemble-with-audio.ffmpeg.txt'
if ((Get-Sha $fltFile) -ne $FilterSha) { throw 'Фильтр сборки не совпал с зафиксированным SHA-256.' }
$flt = @([IO.File]::ReadAllLines($fltFile))
if ($flt[0] -cne ('[0:v]' + $OpenChain + '[v0];') -or $flt[1] -cne ('[1:v]' + $CChain + '[v1];') -or $flt[2] -cne ('[2:v]' + $DChain + '[v2];')) { throw 'Цепочки видео в фильтре сборки не совпали с ep003_lib.ps1.' }
$plan = Get-Content -Raw -LiteralPath $PlanFile | ConvertFrom-Json -AsHashtable
$vt = @{}; foreach ($t in $plan.video_tasks) { $vt[$t.id] = $t }
if ([double]$plan.budget.authorized_cap -ne $Cap -or -not $plan.budget.cap_authorized -or [int]$plan.target_master.frames -ne 384 -or [int]$plan.existing_opening.frames -ne 168 -or [int]$plan.existing_opening.last_frame_index -ne 167 -or
  [int]$vt.C.request_template.input.duration -ne 5 -or [int]$vt.D.request_template.input.duration -ne 4 -or -not $vt.C.request_template.input.Contains('last_frame_url') -or $vt.D.request_template.input.Contains('last_frame_url')) { throw 'plan.json не соответствует пакету 634 / C 5 с first+last / D 4 с first-only / 384 кадра.' }

# ---------- готовое начало: SHA-256, 168 кадров / 7 с со звуком, кадр 167 = opening-lastframe.png попиксельно ----------
if ((Get-Sha $Opening) -ne $OpeningSha) { throw 'Готовое начало не совпало по SHA-256 с plan.json.' }
if ((Get-Sha $OpeningLast) -ne $OpeningLastSha) { throw 'Кадр 167 начала (PNG) не совпал по SHA-256 с plan.json.' }
$op = (ffprobe -v error -count_frames -show_entries 'stream=codec_type,codec_name,width,height,r_frame_rate,nb_read_frames,sample_rate,channels,duration' -of json $Opening | Out-String) | ConvertFrom-Json
$ov = @($op.streams | Where-Object codec_type -eq 'video')[0]; $oa = @($op.streams | Where-Object codec_type -eq 'audio')[0]
if ([int]$ov.nb_read_frames -ne 168 -or $ov.r_frame_rate -ne '24/1' -or [int]$ov.width -ne 720 -or [int]$ov.height -ne 1280 -or [Math]::Abs([double]::Parse($ov.duration, $Inv) - 7.0) -gt 0.01) { throw ('Начало: ожидалось 720×1280, 24 fps, 168 кадров, 7 с; получено ' + $ov.width + '×' + $ov.height + ', ' + $ov.r_frame_rate + ', ' + $ov.nb_read_frames + ', ' + $ov.duration) }
if (-not $oa -or $oa.codec_name -ne 'aac' -or [Math]::Abs([double]::Parse($oa.duration, $Inv) - 7.0) -gt 0.05) { throw 'Начало: нет AAC-звука на 7 с.' }
$fr = @(ffmpeg -v error -i $Opening -vf $OpenChain -an -f framemd5 - 2>$null | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($fr.Count -ne 168) { throw ('Начало после нормализации даёт ' + $fr.Count + ' кадров, ожидалось 168.') }
$md5Open = (@(ffmpeg -v error -i $Opening -vf ($OpenChain + ',select=eq(n\,167),format=rgb24') -frames:v 1 -fps_mode passthrough -an -f framemd5 - 2>$null | Where-Object { $_ -and -not $_.StartsWith('#') })[0] -split ',')[-1].Trim()
$md5Png = (@(ffmpeg -v error -i $OpeningLast -vf 'format=rgb24' -frames:v 1 -f framemd5 - 2>$null | Where-Object { $_ -and -not $_.StartsWith('#') })[0] -split ',')[-1].Trim()
if (-not $md5Open -or $md5Open -ne $md5Png) { throw ('Кадр 167 начала не равен opening-lastframe.png попиксельно (rgb24 md5 ' + $md5Open + ' / ' + $md5Png + ').') }

# ---------- свежие цены по публичной таблице (бесплатно, без ключа) ----------
function Get-PriceRows([string]$q) {
  $r = Invoke-RestMethod -Uri 'https://api.kie.ai/client/v1/model-pricing/page' -Method Post -ContentType 'application/json' -Body (@{ pageNum = 1; pageSize = 50; modelDescription = $q; interfaceType = '' } | ConvertTo-Json -Compress) -TimeoutSec 30 -SkipHttpErrorCheck
  if ($r.code -ne 200) { throw ('Таблица цен: код ' + $r.code + ' ' + $r.msg + '. Цена неизвестна — не активирую.') }
  @($r.data.records)
}
$nb = @(Get-PriceRows 'nano banana 2' | Where-Object { $_.modelDescription -eq 'Google nano banana 2, 2K' })
$sd = @(Get-PriceRows 'seedance-2' | Where-Object { $_.modelDescription -eq 'bytedance/seedance-2, 720p no video input' })
if ($nb.Count -ne 1 -or $sd.Count -ne 1) { throw 'В таблице цен не найдены строки «Google nano banana 2, 2K» и «bytedance/seedance-2, 720p no video input» — цена неизвестна, не активирую.' }
if ([double]$nb[0].creditPrice -ne $ImagePrice -or $nb[0].creditUnit -ne 'per image' -or [double]$sd[0].creditPrice -ne $VideoPerSec -or $sd[0].creditUnit -ne 'per second') {
  throw ('Тариф изменился: nano-banana-2 2K = ' + $nb[0].creditPrice + ' ' + $nb[0].creditUnit + ', seedance-2 720p = ' + $sd[0].creditPrice + ' ' + $sd[0].creditUnit + '. Пересчитать $Stages и бюджет до активации.')
}
$base = 3 * $ImagePrice + (5 + 4) * $VideoPerSec
$reserve = 2 * $ImagePrice + 5 * $VideoPerSec
if ($base -gt $Cap) { throw ('Базовая стоимость ' + $base + ' выше лимита ' + $Cap + ' — не активирую.') }

# ---------- баланс ----------
Set-Key
try { $bal = Get-Balance } finally { $env:KIE_API_KEY = $null }
if ($bal -lt $base) { throw ('Баланс ' + $bal.ToString($Inv) + ' меньше базового пакета ' + $base + ': не хватает ' + [Math]::Round($base - $bal, 2).ToString($Inv) + ' кр. Генерации не запускаю, счёт не пополняю.') }

# ---------- промпты в refs ----------
$st = New-Stamp
$prompts = @()
foreach ($t in @($plan.image_tasks) + @($plan.video_tasks)) {
  $src = Join-Path $Dl ($t.prompt_file -replace '/', '__')
  $dst = Join-Path $Refs ($Pfx + '_' + [IO.Path]::GetFileName($t.prompt_file))
  if (Test-Path -LiteralPath $dst) { throw ('Промпт ' + $dst + ' уже есть.') }
  if ((Get-Sha $src) -ne $t.prompt_sha256) { throw ('Промпт ' + $src + ' не совпал с plan.json.') }
  [IO.File]::Copy($src, $dst)
  if ((Get-Sha $dst) -ne $t.prompt_sha256) { throw ('Копия ' + $dst + ' не совпала по SHA-256.') }
  $log = $dst -replace '\.txt$', '.log.txt'
  [IO.File]::WriteAllLines($log, [string[]]@(
      ([IO.Path]::GetFileName($dst) + ' | промпт ' + $t.id + ' ' + $Episode + ' | ' + (Get-Item -LiteralPath $dst).Length + ' B | sha256=' + $t.prompt_sha256 + ' | сохранено ' + $st),
      ('источник: git ' + $Commit + ':episodes/EP003/' + $t.prompt_file + ' (https://github.com/sINte3/CartoonReels/blob/' + $Commit + '/episodes/EP003/' + $t.prompt_file + '), SHA-256 совпал с plan.json того же коммита')
    ), $Utf8)
  $prompts += [ordered]@{ id = $t.id; file = $dst; sha256 = $t.prompt_sha256 }
}
$jp = Join-Path $Gen ($Pfx + '_journal_' + $st + '.jsonl')
[IO.File]::WriteAllText($jp, '', $Utf8)
Add-Journal ([ordered]@{
    type         = 'activation'
    source       = 'Сообщение пользователя в чате Claude Code 09.11.2026: «Выполни EP003 «Кому медаль?» целиком по инструкции: https://raw.githubusercontent.com/sINte3/CartoonReels/025aad9374f5cfc27323c10125dbe4a4daec532b/episodes/EP003/CLAUDE_PRODUCE_FULL_RU.md Разрешаю новый расход до 634 кредитов: — три опорных изображения; — видео C на 5 секунд и D на 4 секунды; — при конкретных дефектах максимум две дополнительные генерации изображений и одну дополнительную видеогенерацию. Это единое поручение без подтверждения каждого шага.»'
    cap          = $Cap
    allowed      = [ordered]@{ baseImages = 3; baseVideos = 2; videoDurations = [ordered]@{ C = 5; D = 4 }; extraImages = 2; extraVideos = 1; maxImageCreates = 5; maxVideoCreates = 3; topUp = $false; otherModelsOrProviders = $false; paidAudioServices = $false; socialPublication = $false; regenerateOpening = $false; rerunEP002 = $false }
    instruction  = [ordered]@{ path = 'episodes/EP003/CLAUDE_PRODUCE_FULL_RU.md'; url = 'https://github.com/sINte3/CartoonReels/blob/' + $Commit + '/episodes/EP003/CLAUDE_PRODUCE_FULL_RU.md'; sha256 = (Get-Sha (Join-Path $Dl 'CLAUDE_PRODUCE_FULL_RU.md')) }
    readme       = [ordered]@{ path = 'episodes/EP003/README.md'; sha256 = (Get-Sha (Join-Path $Dl 'README.md')) }
    commit       = $Commit
    planSha256   = $PlanSha
    filterSha256 = $FilterSha
    hero         = [ordered]@{ file = $Hero; sha256 = $HeroSha; size = '941x1672' }
    opening      = [ordered]@{ source = 'deliverables/ep002/EP002_timing_7s_sound_720p.mp4 @ ' + $Commit; sha256 = $OpeningSha; frames = 168; seconds = 7.0; audio = 'aac ' + $oa.sample_rate + ' Hz, ' + $oa.channels + ' ch'
      lastFrame = [ordered]@{ source = 'episodes/EP003/references/opening-lastframe.png'; sha256 = $OpeningLastSha; frameIndex = 167; rgb24Md5 = $md5Png; equalsOpeningFrame167 = $true; chain = $OpenChain }
      regenerated = $false; gainReapplied = $false }
    prompts      = $prompts
    prices       = [ordered]@{
      checkedAt       = (Now)
      source          = 'POST https://api.kie.ai/client/v1/model-pricing/page (данные таблицы kie.ai/pricing)'
      nanoBanana2_2K  = '«' + $nb[0].modelDescription + '» — ' + $nb[0].creditPrice + ' кр ' + $nb[0].creditUnit + ' ($' + $nb[0].usdPrice + ')'
      seedance2_720p  = '«' + $sd[0].modelDescription + '» — ' + $sd[0].creditPrice + ' кр ' + $sd[0].creditUnit + ' ($' + $sd[0].usdPrice + '); first+last и first-only — картинки, это строка без видео-входа; C 5 с = 205, D 4 с = 164'
      audio           = 'отдельной строки за generate_audio нет; в EP002 видео со звуком списали ровно 41 кр/с'
      schemas         = 'docs.kie.ai/market/google/nanobanana2.md: image_input ≤ 10 URL, resolution 1K/2K/4K, output_format png/jpg; docs.kie.ai/market/bytedance/seedance-2.md (проверено 09.11.2026): «Image-to-Video (First Frame)», «Image-to-Video (First & Last Frames)» и Reference-to-Video — взаимоисключающие сценарии, first/last не смешивать с reference_*; last_frame_url необязателен; duration integer 4–15; generate_audio boolean (по умолчанию true)'
    }
    expected     = [ordered]@{ base = $base; reserveMax = $reserve; maxTotal = $base + $reserve; formula = '3×12 + 5×41 + 4×41 = 405; резерв 2×12 + 5×41 = 229'; remainingMandatoryAfter = [ordered]@{ K0 = 393; K1 = 381; C = 176; K2 = 164; D = 0 } }
    balanceStart = $bal
  })
'Журнал: ' + $jp
'Цены: nano-banana-2 2K ' + $nb[0].creditPrice + ' кр, seedance-2 720p ' + $sd[0].creditPrice + ' кр/с; база ' + $base + ', максимум ' + ($base + $reserve) + ' ≤ ' + $Cap
'Начало: 168 кадров / 7 с, кадр 167 = opening-lastframe.png (rgb24 md5 ' + $md5Png + ')'
'Стартовый баланс: ' + $bal.ToString($Inv) + ' кр'
'Промпты в refs: ' + (($prompts | ForEach-Object { [IO.Path]::GetFileName($_.file) }) -join ', ')
