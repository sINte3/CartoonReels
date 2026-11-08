# ep002_activate.ps1 — запись пакетного разрешения пользователя в журнал, копии промптов в refs, стартовый баланс. Без расходов.
. (Join-Path $PSScriptRoot 'ep002_lib.ps1')
if (@(Get-ChildItem -LiteralPath $Gen -Filter ($Pfx + '_journal_*.jsonl') -File).Count) { throw 'Журнал пакета уже существует — повторная активация не нужна.' }
if (@(Get-ChildItem -LiteralPath $Gen -Filter ($Pfx + '_*.task.json') -File).Count) { throw 'Записи задач EP002 уже есть без журнала — разобраться до активации.' }
if ((Get-Sha $PlanFile) -ne $PlanSha) { throw 'plan.json не совпал с зафиксированным коммитом.' }
if ((Get-Sha $Hero) -ne $HeroSha) { throw 'Исходник героя не совпал по SHA-256.' }
if ((Get-Sha (Join-Path $Dl 'assemble-with-audio.ffmpeg.txt')) -ne $FilterSha) { throw 'Фильтр сборки не совпал с зафиксированным SHA-256.' }
$plan = Get-Content -Raw -LiteralPath $PlanFile | ConvertFrom-Json -AsHashtable
if ([double]$plan.budget.proposed_cap_credits -ne $Cap -or (@($plan.budget.base_video_durations_seconds) -join ',') -ne '4,5' -or [int]$plan.target_master.frames -ne 216) { throw 'plan.json не соответствует пакету 640 / 4+5 с / 216 кадров.' }
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
      ('источник: git ' + $Commit + ':episodes/EP002/' + $t.prompt_file + ' (https://github.com/sINte3/CartoonReels/blob/' + $Commit + '/episodes/EP002/' + $t.prompt_file + '), SHA-256 совпал с plan.json того же коммита')
    ), $Utf8)
  $prompts += [ordered]@{ id = $t.id; file = $dst; sha256 = $t.prompt_sha256 }
}
Set-Key
try { $bal = Get-Balance } finally { $env:KIE_API_KEY = $null }
if ($bal -lt 405) { throw ('Баланс ' + $bal + ' меньше базового пакета 405 — не активирую.') }
$jp = Join-Path $Gen ($Pfx + '_journal_' + $st + '.jsonl')
[IO.File]::WriteAllText($jp, '', $Utf8)
Add-Journal ([ordered]@{
    type         = 'activation'
    source       = 'Сообщение пользователя в чате Claude Code 08.11.2026: «Выполни EP002 «Силач понарошку» целиком со звуком. Разрешаю расходы через Kie AI в пределах 640 кредитов: — 3 исходных изображения; — 2 видео: A на 4 секунды и B на 5 секунд; — при конкретных дефектах максимум 2 дополнительные генерации изображений и 1 дополнительную видеогенерацию. Это единое разрешение на весь пакет. Подтверждение после каждого шага не требуется.»'
    cap          = $Cap
    allowed      = [ordered]@{ baseImages = 3; baseVideos = 2; videoDurations = [ordered]@{ A = 4; B = 5 }; extraImages = 2; extraVideos = 1; maxImageCreates = 5; maxVideoCreates = 3; topUp = $false; otherModelsOrProviders = $false; paidAudioServices = $false }
    instruction  = [ordered]@{ path = 'episodes/EP002/CLAUDE_PRODUCE_FULL_RU.md'; url = 'https://github.com/sINte3/CartoonReels/blob/' + $Commit + '/episodes/EP002/CLAUDE_PRODUCE_FULL_RU.md'; sha256 = (Get-Sha (Join-Path $Dl 'CLAUDE_PRODUCE_FULL_RU.md')) }
    readme       = [ordered]@{ path = 'episodes/EP002/README.md'; sha256 = (Get-Sha (Join-Path $Dl 'README.md')) }
    commit       = $Commit
    planSha256   = $PlanSha
    filterSha256 = $FilterSha
    hero         = [ordered]@{ file = $Hero; sha256 = $HeroSha; size = '941x1672' }
    prompts      = $prompts
    prices       = [ordered]@{
      checkedAt      = '2026-11-08 17:44 Asia/Tashkent'
      source         = 'POST https://api.kie.ai/client/v1/model-pricing/page (данные таблицы kie.ai/pricing) + описания цен на kie.ai/nano-banana-2 и kie.ai/seedance-2-0'
      nanoBanana2_2K = '«Google nano banana 2, 2K» — 12 кр ($0.06) за изображение; у модели 3 варианта (1K 8 / 2K 12 / 4K 18), отдельной цены за число референсов нет'
      seedance2_720p = '«bytedance/seedance-2, 720p no video input» — 41 кр/с ($0.205/s); first+last frame — картинки, это строка без видео-входа; A 4 с = 164, B 5 с = 205'
      audio          = 'отдельной строки за generate_audio нет: у bytedance/seedance-2 8 вариантов = 4 разрешения × с/без видео-входа; документация: «Native Audio — on by default»; в EP001 V3 4 с со звуком списали 164'
      schemas        = 'docs.kie.ai/market/google/nanobanana2.md: image_input ≤ 10 URL, resolution 1K/2K/4K, output_format png/jpg; docs.kie.ai/market/bytedance/seedance-2.md: duration integer 4–15, generate_audio boolean, first/last frame не смешивать с reference_*'
    }
    expected     = [ordered]@{ base = 405; reserveMax = 229; maxTotal = 634; formula = '3×12 + 4×41 + 5×41 = 405; резерв 2×12 + 5×41 = 229' }
    balanceStart = $bal
  })
'Журнал: ' + $jp
'Стартовый баланс: ' + $bal + ' кр'
'Промпты в refs: ' + (($prompts | ForEach-Object { [IO.Path]::GetFileName($_.file) }) -join ', ')
