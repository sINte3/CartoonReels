# Сухой прогон ПРОДОЛЖЕНИЯ пакета EP003 по ревизии 2 на моках. Исходное состояние — копия реального журнала и записей
# из E:\Generations (48 кр, 4 изображения, повторы 2/2, K0 принят, K1 ×3 отклонены) во временном каталоге; пути в журнале
# и .task.json переписаны на копию, сами файлы E:\Generations не меняются. Поддельный ключ, сеть закрыта прокси и моками.
# Сценарий A: смена тарифа / нехватка денег до ревизии → ревизия → C (только first K0) → отказ → C-retry1 (общий видеоповтор)
#             → кадр 119 → K2 (последнее изображение) → D → запрет повтора D → сборка 16 с / 384 кадра.
# Сценарий B: ревизия → C → K2 отклонён → K2-retry невозможен → D не запускается (остановка до D);
#             затем K2 принят → D → отказ → D-retry1 (общий видеоповтор использован на D).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$prod = Split-Path $here
$repo = Split-Path (Split-Path (Split-Path $prod))
$heroSrc = Join-Path $repo 'deliverables\lookdev-02\hero-3d-keyframe.png'
$realGen = 'E:\Generations'
$U8 = [Text.UTF8Encoding]::new($false)
$root = Join-Path ([IO.Path]::GetTempPath()) ('kie-executor-ep003-continue-dryrun_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$I = Join-Path $root 'inputs'
New-Item -ItemType Directory -Path $root | Out-Null
& (Join-Path $prod 'export-inputs.ps1') -Dest $I
$add = Join-Path $root 'CartoonReels_EP003_dryrun_addendum.prompt.en.txt'
[IO.File]::WriteAllText($add, "Targeted correction for the dry run: lift the dumbbell higher with a wider floor gap and keep both forepaws on the medal ribbon.`n")
function Snap { if (Test-Path -LiteralPath $realGen) { $f = @(Get-ChildItem -LiteralPath $realGen -Recurse -File); '' + $f.Count + '/' + ($f | Measure-Object Length -Sum).Sum + '/' + (($f | Sort-Object LastWriteTimeUtc | Select-Object -Last 1).LastWriteTimeUtc.Ticks) } }
$snapBefore = Snap

# Копия реального состояния пакета: журнал и .task.json с переписанными путями, остальное байт в байт.
function New-Scenario([string]$name) {
  $T = Join-Path $root ($name + '\gen'); $M = Join-Path $root ($name + '\mock')
  New-Item -ItemType Directory -Path (Join-Path $T 'refs'), $M | Out-Null
  Copy-Item -LiteralPath $heroSrc -Destination (Join-Path $T 'refs')
  Get-ChildItem -LiteralPath (Join-Path $realGen 'refs') -Filter 'CartoonReels_EP003_*' -File | Copy-Item -Destination (Join-Path $T 'refs')
  $escReal = 'E:\\Generations'; $escT = $T.Replace('\', '\\')
  foreach ($f in Get-ChildItem -LiteralPath $realGen -Filter 'CartoonReels_EP003_*' -File) {
    $dst = Join-Path $T $f.Name
    if ($f.Name -match '(\.jsonl|\.task\.json)$') {
      $txt = [IO.File]::ReadAllText($f.FullName).Replace($escReal, $escT)
      if ($txt.Contains('E:\\Generations') -or $txt.Contains('E:\Generations')) { throw ('В копии ' + $f.Name + ' остался путь E:\Generations') }
      [IO.File]::WriteAllText($dst, $txt, $U8)
    } else { Copy-Item -LiteralPath $f.FullName -Destination $dst }
  }
  ffmpeg -v error -f lavfi -i 'testsrc2=size=1536x2752:rate=1' -frames:v 1 (Join-Path $M 'result_image.png')
  ffmpeg -v error -f lavfi -i 'testsrc2=size=720x1280:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=44100' -t 4.0417 -c:v libx264 -pix_fmt yuv420p -c:a aac (Join-Path $M 'result_video4.mp4')
  ffmpeg -v error -f lavfi -i 'testsrc=size=720x1280:rate=24' -f lavfi -i 'sine=frequency=220:sample_rate=44100' -t 5.0417 -c:v libx264 -pix_fmt yuv420p -c:a aac (Join-Path $M 'result_video5.mp4')
  Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'ok'
  @{ balance = 1172.99; n = 0; tasks = @{}; charged = @{} } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $M 'state.json') -Encoding utf8
  $env:EP003_TEST_GEN = $T; $env:EP003_MOCK = $M
  $j = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP003_journal_*.jsonl')[0].FullName
  $recs = @{}; foreach ($r in Get-ChildItem -LiteralPath $T -Filter '*.task.json') { $recs[$r.Name] = (Get-FileHash -Algorithm SHA256 $r.FullName).Hash }
  [ordered]@{ T = $T; M = $M; journal = $j; journalLines = @(Get-Content -LiteralPath $j -Encoding utf8); recs = $recs }
}
$env:KIE_EXEC_INPUTS = $I
$env:HTTP_PROXY = 'http://127.0.0.1:9'; $env:HTTPS_PROXY = 'http://127.0.0.1:9'; $env:ALL_PROXY = 'http://127.0.0.1:9'
$pass = 0; $failn = 0
function Step([string]$title, [string]$script, [string[]]$a, [bool]$expectOk, [string]$expectText = '') {
  $cmd = ". '" + (Join-Path $here 'mocks.ps1') + "'; & '" + (Join-Path $prod $script) + "' " + (($a | ForEach-Object { if ($_ -match '^-[A-Za-z]+$') { $_ } else { "'" + ($_ -replace "'", "''") + "'" } }) -join ' ')
  $out = (pwsh -NoProfile -Command $cmd 2>&1 | Out-String).Trim()
  $ok = ($LASTEXITCODE -eq 0)
  $good = ($ok -eq $expectOk) -and (-not $expectText -or $out -match $expectText)
  if ($good) { $script:pass++; $m = 'PASS' } else { $script:failn++; $m = 'FAIL' }
  $short = (($out -split "`n" | Select-Object -Last 2) -join ' / ') -replace '\s+', ' '
  '{0} {1} — exit {2}: {3}' -f $m, $title, $LASTEXITCODE, ($short.Substring(0, [Math]::Min(240, $short.Length)))
  if (-not $good) { '      полный вывод: ' + ($out -replace '\s+', ' ').Substring(0, [Math]::Min(1500, ($out -replace '\s+', ' ').Length)) }
}
function Check([string]$title, [bool]$cond) { if ($cond) { $script:pass++; 'PASS ' + $title } else { $script:failn++; 'FAIL ' + $title } }
function Calls($S) { @(Get-Content -LiteralPath (Join-Path $S.M 'calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable }) }
function Keys($h) { (@($h.Keys) | Sort-Object) -join ',' }
function Journal($S) { @(Get-Content -LiteralPath $S.journal -Encoding utf8) }
function JE($S) { @(Journal $S | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable }) }
function TaskRec($S, [string]$label) { $f = @(Get-ChildItem -LiteralPath $S.T -Filter ('CartoonReels_EP003_' + $label + '_2*.task.json')); if ($f.Count -eq 1) { Get-Content -Raw $f[0].FullName | ConvertFrom-Json -AsHashtable } }
function RecsUnchanged($S) { foreach ($k in $S.recs.Keys) { if ((Get-FileHash -Algorithm SHA256 (Join-Path $S.T $k)).Hash -ne $S.recs[$k]) { return $false } }; $true }
function PrefixKept($S) { $now = Journal $S; if ($now.Count -lt $S.journalLines.Count) { return $false }; for ($i = 0; $i -lt $S.journalLines.Count; $i++) { if ($now[$i] -cne $S.journalLines[$i]) { return $false } }; $true }
$plan = Get-Content -Raw -LiteralPath (Join-Path $I 'plan.json') | ConvertFrom-Json -AsHashtable
function PlanPrompt([string]$id) { (@(@($plan.image_tasks) + @($plan.video_tasks) | Where-Object { $_.id -eq $id }))[0].request_template.input.prompt }
$addText = [IO.File]::ReadAllText($add).TrimEnd("`r", "`n")
$cFile = [IO.File]::ReadAllText((Join-Path $I 'prompts__C-solo-lift-first-frame.prompt.en.txt'))
$inv = [Globalization.CultureInfo]::InvariantCulture
function Ssim([string]$a, [string]$b) { $o = (ffmpeg -hide_banner -nostats -i $a -i $b -lavfi '[0:v]format=yuv420p[x];[1:v]format=yuv420p[y];[x][y]ssim' -f null - 2>&1 | Out-String); if ($o -match 'All:([\d.]+)') { [double]::Parse($Matches[1], $inv) } else { -1 } }
function FrameAt([string]$f, [int]$n, [string]$chain, [string]$out) { ffmpeg -v error -y -i $f -vf ($chain + ',select=eq(n\,' + $n + ')') -frames:v 1 -fps_mode passthrough $out; $out }

# =================== Сценарий A ===================
'=== Сценарий A: C → отказ → C-retry1 → K2 → D → сборка ==='
$A = New-Scenario 'A'
Check 'A: копия состояния — 48 кр, 4 изображения, K0 принят, K1 ×3 отклонены' ((@(JE $A | Where-Object { $_.type -eq 'result' } | ForEach-Object { [double]$_.creditsConsumed }) | Measure-Object -Sum).Sum -eq 48 -and @(Get-ChildItem -LiteralPath $A.T -Filter '*.task.json').Count -eq 4 -and @(JE $A | Where-Object { $_.type -eq 'reject' -and $_.stage -eq 'K1' }).Count -eq 3)
Set-Content -LiteralPath (Join-Path $A.M 'nbprice.txt') -Value '13'
Step 'A: ревизия отклонена при смене тарифа' 'ep003_revise.ps1' @() $false 'Тариф изменился'
Remove-Item -LiteralPath (Join-Path $A.M 'nbprice.txt')
@{ balance = 300.0; n = 0; tasks = @{}; charged = @{} } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $A.M 'state.json') -Encoding utf8
Step 'A: ревизия отклонена при нехватке денег (300 < 381, не хватает 81)' 'ep003_revise.ps1' @() $false 'не хватает 81 кр'
@{ balance = 1172.99; n = 0; tasks = @{}; charged = @{} } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $A.M 'state.json') -Encoding utf8
Check 'A: после двух отказов журнал не изменился' ((Journal $A).Count -eq $A.journalLines.Count -and (PrefixKept $A))
Step 'A: C до записи ревизии отклонён' 'ep003_create.ps1' @('-Label', 'C') $false 'не записана в журнал'
Step 'A: активация к ревизии 2 не применяется' 'ep003_activate.ps1' @() $false 'уже существует|не применяется'
Step 'A: ревизия записана, счётчики сохранены' 'ep003_revise.ps1' @() $true 'факт 48 кр, изображений 4 \(повторов 2\), видео 0 \(повторов 0\)'
Step 'A: повторная ревизия отклонена' 'ep003_revise.ps1' @() $false 'уже записана'
Step 'A: новый K1 запрещён' 'ep003_create.ps1' @('-Label', 'K1') $false 'закрыт в ревизии 2'
Step 'A: K1-retry3 запрещён' 'ep003_create.ps1' @('-Label', 'K1-retry3', '-AddendumFile', $add) $false 'закрыт в ревизии 2'
Step 'A: новый K0 запрещён' 'ep003_create.ps1' @('-Label', 'K0-retry1', '-AddendumFile', $add) $false 'закрыт в ревизии 2'
Step 'A: принять отклонённый K1-retry2 нельзя' 'ep003_decide.ps1' @('-Label', 'K1-retry2', '-Decision', 'accept', '-Reason', 'dry bypass attempt') $false 'принимать их нельзя'
Step 'A: K2 до C отклонён' 'ep003_create.ps1' @('-Label', 'K2') $false 'не принят'
Step 'A: D до C отклонён' 'ep003_create.ps1' @('-Label', 'D') $false 'не принят'
Step 'A: C (только first K0, без K1): 205 кр, после 176, максимум 429' 'ep003_create.ps1' @('-Label', 'C') $true 'taskId mocktask0001 .*ожидается 205 кр.*"actualBefore":48.0.*"remainingMandatoryAfter":176.0,"projectedMax":429.0,"cap":634'
Step 'A: повторный C отклонён' 'ep003_create.ps1' @('-Label', 'C') $false 'уже'
Step 'A: перекрывающийся K2 при неопрошенном C отклонён' 'ep003_create.ps1' @('-Label', 'K2') $false 'невыясненная'
Step 'A: опрос C' 'ep003_poll.ps1' @('-Label', 'C') $true 'creditsConsumed = 205'
Step 'A: сохранение C' 'ep003_save.ps1' @('-Label', 'C') $true '"audio":true'
Step 'A: отказ C (тест)' 'ep003_decide.ps1' @('-Label', 'C', '-Decision', 'reject', '-Reason', 'dry defect: plates still touch the floor') $true 'reject C'
Step 'A: C-retry1 — общий видеоповтор: 48+205+205+176 = 634' 'ep003_create.ps1' @('-Label', 'C-retry1', '-AddendumFile', $add) $true 'taskId mocktask0002 .*"actualBefore":253.0.*"projectedMax":634.0'
Step 'A: опрос C-retry1' 'ep003_poll.ps1' @('-Label', 'C-retry1') $true 'creditsConsumed = 205'
Step 'A: сохранение C-retry1' 'ep003_save.ps1' @('-Label', 'C-retry1') $true '"audio":true'
Step 'A: C-retry2 невозможен (резерв видео 1)' 'ep003_decide.ps1' @('-Label', 'C-retry1', '-Decision', 'reject', '-Reason', 'dry limit test') $true 'reject'
Step 'A: C-retry2 отклонён' 'ep003_create.ps1' @('-Label', 'C-retry2', '-AddendumFile', $add) $false 'Резерв исправлений \(video 1\)|Бюджет'
Step 'A: принять C-retry1' 'ep003_decide.ps1' @('-Label', 'C-retry1', '-Decision', 'accept', '-Reason', 'dry') $true 'accept C-retry1'
Step 'A: кадр 119 принятого C-retry1' 'ep003_clast.ps1' @() $true '720,1280.*кадр 119 сверен'
Step 'A: K2 — пятое изображение: 48+410+12+164 = 634' 'ep003_create.ps1' @('-Label', 'K2') $true 'taskId mocktask0003 .*"actualBefore":458.0.*"remainingMandatoryAfter":164.0,"projectedMax":634.0'
Step 'A: опрос K2' 'ep003_poll.ps1' @('-Label', 'K2') $true 'creditsConsumed = 12'
Step 'A: сохранение K2' 'ep003_save.ps1' @('-Label', 'K2') $true 'png'
Step 'A: отказ K2 (тест)' 'ep003_decide.ps1' @('-Label', 'K2', '-Decision', 'reject', '-Reason', 'dry limit test') $true 'reject K2'
Step 'A: K2-retry1 отклонён (лимит изображений 5)' 'ep003_create.ps1' @('-Label', 'K2-retry1', '-AddendumFile', $add) $false 'Лимит отправок \(image 5\)'
Step 'A: D при отклонённом K2 отклонён' 'ep003_create.ps1' @('-Label', 'D') $false 'Этап K2 не принят'
Step 'A: принять K2' 'ep003_decide.ps1' @('-Label', 'K2', '-Decision', 'accept', '-Reason', 'dry') $true 'accept K2'
Step 'A: D (только first K2): 164 кр, максимум 634' 'ep003_create.ps1' @('-Label', 'D') $true 'taskId mocktask0004 .*ожидается 164 кр.*"actualBefore":470.0.*"remainingMandatoryAfter":0.0,"projectedMax":634.0'
Set-Content -LiteralPath (Join-Path $A.M 'scenario.txt') -Value 'pollslow'
Step 'A: опрос D остановлен на generating' 'ep003_poll.ps1' @('-Label', 'D', '-Minutes', '0') $true 'Ещё идёт: D taskId mocktask0004'
Step 'A: баланс с D в работе (pending 164)' 'ep003_balance_check.ps1' @() $true 'actual=470 pending=164'
Set-Content -LiteralPath (Join-Path $A.M 'scenario.txt') -Value 'ok'
Step 'A: опрос D возобновлён по taskId' 'ep003_poll.ps1' @('-Label', 'D') $true 'creditsConsumed = 164'
Step 'A: сохранение D' 'ep003_save.ps1' @('-Label', 'D') $true '"audio":true'
Step 'A: отказ D (тест)' 'ep003_decide.ps1' @('-Label', 'D', '-Decision', 'reject', '-Reason', 'dry limit test') $true 'reject D'
Step 'A: D-retry1 отклонён (видеоповтор уже на C, лимит 3 видео)' 'ep003_create.ps1' @('-Label', 'D-retry1', '-AddendumFile', $add) $false 'Лимит отправок \(video 3\)|Резерв исправлений'
Step 'A: принять D' 'ep003_decide.ps1' @('-Label', 'D', '-Decision', 'accept', '-Reason', 'dry') $true 'accept D'
Step 'A: баланс 1220.99 − 634 = 586.99' 'ep003_balance_check.ps1' @() $true 'balance=586.99 actual=634 pending=0 images=5 \(retry 2\) videos=3 \(retry 1\)'
Step 'A: сборка -MeasureOnly' 'ep003_assemble.ps1' @('-MeasureOnly') $true 'loud_used'
Step 'A: сборка 16 с / 384 кадра' 'ep003_assemble.ps1' @('-GainC', '1.5') $true '"frames_384": true'

$ca = Calls $A
$ctA = @($ca | Where-Object call -eq 'createTask')
$upA = @($ca | Where-Object call -eq 'upload')
Check 'A: createTask 4 раза (C, C-retry1, K2, D); K1/K0/C-retry2/K2-retry1/D-retry1 не отправлены' ($ctA.Count -eq 4)
Check 'A: ни одной загрузки K1; загрузки только K0 (C ×2), C-last+K0+герой (K2), K2 (D)' (@($upA | Where-Object { $_.name -match '_K1' }).Count -eq 0 -and $upA.Count -eq 6 -and $upA[0].name -match '^CartoonReels_EP003_K0_' -and $upA[1].name -match '^CartoonReels_EP003_K0_' -and $upA[2].name -match 'C-lastframe' -and $upA[5].name -match '^CartoonReels_EP003_K2_')
foreach ($ix in 0, 1) {
  $cb0 = $ctA[$ix].body
  Check ('A: ' + @('C', 'C-retry1')[$ix] + ' — seedance-2, ровно 6 полей без last_frame_url, first = K0, 5 с целым, 720p, 9:16, звук') ($cb0.model -eq 'bytedance/seedance-2' -and (Keys $cb0.input) -eq 'aspect_ratio,duration,first_frame_url,generate_audio,prompt,resolution' -and -not $cb0.input.ContainsKey('last_frame_url') -and $cb0.input.first_frame_url -match 'CartoonReels_EP003_K0_' -and $cb0.input.duration -is [long] -and $cb0.input.duration -eq 5 -and $cb0.input.resolution -eq '720p' -and $cb0.input.aspect_ratio -eq '9:16' -and $cb0.input.generate_audio -eq $true)
}
Check 'A: промпт C = plan.json ревизии 2 = файл C-solo-lift-first-frame' ($ctA[0].body.input.prompt -ceq (PlanPrompt 'C') -and $ctA[0].body.input.prompt -ceq $cFile)
Check 'A: C-retry1 = промпт C + перевод строки + правка' ($ctA[1].body.input.prompt -ceq ($cFile + "`n" + $addText))
Check 'A: K2 — 3 референса (кадр 119 C-retry1, K0, герой), промпт = plan.json' (@($ctA[2].body.input.image_input).Count -eq 3 -and $ctA[2].body.input.image_input[0] -match 'C-lastframe' -and $ctA[2].body.input.image_input[1] -match 'EP003_K0_' -and $ctA[2].body.input.image_input[2] -match 'hero' -and $ctA[2].body.input.prompt -ceq (PlanPrompt 'K2'))
Check 'A: D — 6 полей без last_frame_url, first = K2, 4 с, промпт = plan.json' ((Keys $ctA[3].body.input) -eq 'aspect_ratio,duration,first_frame_url,generate_audio,prompt,resolution' -and -not $ctA[3].body.input.ContainsKey('last_frame_url') -and $ctA[3].body.input.first_frame_url -match 'EP003_K2_' -and $ctA[3].body.input.duration -eq 4 -and $ctA[3].body.input.prompt -ceq (PlanPrompt 'D'))
$jeA = JE $A
$rev = @($jeA | Where-Object { $_.type -eq 'revision' })
Check 'A: одна запись revision: коммит/план ревизии 2, факт 48, изображений 4 (повторов 2), видео 0, бюджет не обнулён' ($rev.Count -eq 1 -and $rev[0].revision -eq 2 -and $rev[0].commit -eq 'f6a9acaf2473eea76148cc9212bb88e6a7e47f80' -and [double]$rev[0].preserved.spentActual -eq 48 -and $rev[0].preserved.imageCreates -eq 4 -and $rev[0].preserved.imageRetries -eq 2 -and $rev[0].preserved.videoCreates -eq 0 -and $rev[0].preserved.budgetReset -eq $false -and [double]$rev[0].remaining.maxTotal -eq 634)
Check 'A: журнал ревизии 1 сохранён как начало файла, старые .task.json не изменились' ((PrefixKept $A) -and (RecsUnchanged $A))
Check 'A: K1 нигде не принят' (@($jeA | Where-Object { $_.type -eq 'accept' -and $_.stage -eq 'K1' }).Count -eq 0)
$clA = @($jeA | Where-Object { $_.type -eq 'clast' })
Check 'A: кадр 119 взят из принятого C-retry1' ($clA.Count -eq 1 -and $clA[0].sourceFile -match 'CartoonReels_EP003_C-retry1_' -and $clA[0].frameIndex -eq 119)
$bud = @('C', 'C-retry1', 'K2', 'D' | ForEach-Object { (TaskRec $A $_).budget })
Check 'A: projectedMax 429 / 634 / 634 / 634, ни одна отправка не выше 634; planCommit = f6a9aca' ([double]$bud[0].projectedMax -eq 429 -and [double]$bud[1].projectedMax -eq 634 -and [double]$bud[2].projectedMax -eq 634 -and [double]$bud[3].projectedMax -eq 634 -and (TaskRec $A 'C').planCommit -eq 'f6a9acaf2473eea76148cc9212bb88e6a7e47f80')
$out720 = @(Get-ChildItem -LiteralPath $A.T -Filter 'CartoonReels_EP003_16s_sound_720p_*.mp4')[0].FullName
$out1080 = @(Get-ChildItem -LiteralPath $A.T -Filter 'CartoonReels_EP003_16s_sound_1080p_*.mp4')[0].FullName
function Pr([string]$f) { (ffprobe -v error -count_frames -show_entries 'stream=codec_type,codec_name,width,height,r_frame_rate,nb_read_frames,sample_rate,channels,duration' -of json $f | Out-String) | ConvertFrom-Json }
$p720 = Pr $out720; $p1080 = Pr $out1080
$v720 = @($p720.streams | Where-Object codec_type -eq 'video')[0]; $a720 = @($p720.streams | Where-Object codec_type -eq 'audio')[0]
$v1080 = @($p1080.streams | Where-Object codec_type -eq 'video')[0]
Check 'A: 720p — 720×1280, 24/1, 384 кадра, AAC 48 кГц стерео, 16 с' ([int]$v720.width -eq 720 -and [int]$v720.height -eq 1280 -and $v720.r_frame_rate -eq '24/1' -and [int]$v720.nb_read_frames -eq 384 -and $a720.codec_name -eq 'aac' -and $a720.sample_rate -eq '48000' -and [int]$a720.channels -eq 2 -and [Math]::Abs([double]::Parse($a720.duration, $inv) - 16.0) -lt 0.05)
Check 'A: 1080p — 1080×1920, 384 кадра' ([int]$v1080.width -eq 1080 -and [int]$v1080.height -eq 1920 -and [int]$v1080.nb_read_frames -eq 384)
$cMp4 = @(Get-ChildItem -LiteralPath $A.T -Filter 'CartoonReels_EP003_C-retry1_*.mp4')[0].FullName
$dMp4 = @(Get-ChildItem -LiteralPath $A.T -Filter 'CartoonReels_EP003_D_*.mp4')[0].FullName
$clast = $clA[0].file
Check 'A: кадр 167 монтажа ≈ кадр 167 начала' ((Ssim (FrameAt $out720 167 'null' (Join-Path $root 'a167.png')) (Join-Path $I 'opening-lastframe.png')) -gt 0.95)
Check 'A: кадр 168 ≈ первый кадр C-retry1 (склейка 168/120)' ((Ssim (FrameAt $out720 168 'null' (Join-Path $root 'a168.png')) (FrameAt $cMp4 0 'fps=24' (Join-Path $root 'ac0.png'))) -gt 0.95)
Check 'A: кадр 287 ≈ извлечённый кадр 119 C' ((Ssim (FrameAt $out720 287 'null' (Join-Path $root 'a287.png')) $clast) -gt 0.95)
Check 'A: кадр 288 ≈ первый кадр D (склейка 288/96)' ((Ssim (FrameAt $out720 288 'null' (Join-Path $root 'a288.png')) (FrameAt $dMp4 0 'fps=24' (Join-Path $root 'ad0.png'))) -gt 0.95)

# =================== Сценарий B ===================
'=== Сценарий B: K2 отклонён → остановка до D; затем общий видеоповтор на D ==='
$B = New-Scenario 'B'
Step 'B: ревизия' 'ep003_revise.ps1' @() $true 'Ревизия 2 записана'
Step 'B: C' 'ep003_create.ps1' @('-Label', 'C') $true 'taskId mocktask0001 .*"projectedMax":429.0'
Step 'B: опрос C' 'ep003_poll.ps1' @('-Label', 'C') $true 'creditsConsumed = 205'
Step 'B: сохранение C' 'ep003_save.ps1' @('-Label', 'C') $true '"audio":true'
Step 'B: принять C' 'ep003_decide.ps1' @('-Label', 'C', '-Decision', 'accept', '-Reason', 'dry') $true 'accept C'
Step 'B: K2 до кадра 119 отклонён' 'ep003_create.ps1' @('-Label', 'K2') $false 'Нет извлечённого'
Step 'B: кадр 119' 'ep003_clast.ps1' @() $true 'кадр 119 сверен'
Step 'B: K2' 'ep003_create.ps1' @('-Label', 'K2') $true 'taskId mocktask0002 .*"projectedMax":429.0'
Step 'B: опрос K2' 'ep003_poll.ps1' @('-Label', 'K2') $true 'creditsConsumed = 12'
Step 'B: сохранение K2' 'ep003_save.ps1' @('-Label', 'K2') $true 'png'
Step 'B: K2 непригоден' 'ep003_decide.ps1' @('-Label', 'K2', '-Decision', 'reject', '-Reason', 'dry defect: medal still on the neck') $true 'reject K2'
Step 'B: K2-retry1 отклонён (лимит изображений 5)' 'ep003_create.ps1' @('-Label', 'K2-retry1', '-AddendumFile', $add) $false 'Лимит отправок \(image 5\)'
Step 'B: D при непригодном K2 отклонён — остановка до D' 'ep003_create.ps1' @('-Label', 'D') $false 'Этап K2 не принят'
Step 'B: принять K2 (тест продолжения)' 'ep003_decide.ps1' @('-Label', 'K2', '-Decision', 'accept', '-Reason', 'dry') $true 'accept K2'
Step 'B: D' 'ep003_create.ps1' @('-Label', 'D') $true 'taskId mocktask0003 .*"projectedMax":429.0'
Step 'B: опрос D' 'ep003_poll.ps1' @('-Label', 'D') $true 'creditsConsumed = 164'
Step 'B: сохранение D' 'ep003_save.ps1' @('-Label', 'D') $true '"audio":true'
Step 'B: отказ D' 'ep003_decide.ps1' @('-Label', 'D', '-Decision', 'reject', '-Reason', 'dry defect: three claps') $true 'reject D'
Step 'B: D-retry1 — общий видеоповтор на D: 429+164 = 593' 'ep003_create.ps1' @('-Label', 'D-retry1', '-AddendumFile', $add) $true 'taskId mocktask0004 .*"actualBefore":429.0.*"projectedMax":593.0'
Step 'B: опрос D-retry1' 'ep003_poll.ps1' @('-Label', 'D-retry1') $true 'creditsConsumed = 164'
Step 'B: сохранение D-retry1' 'ep003_save.ps1' @('-Label', 'D-retry1') $true '"audio":true'
Step 'B: отказ D-retry1 (тест)' 'ep003_decide.ps1' @('-Label', 'D-retry1', '-Decision', 'reject', '-Reason', 'dry limit test') $true 'reject'
Step 'B: D-retry2 отклонён (видеорезерв 1 использован)' 'ep003_create.ps1' @('-Label', 'D-retry2', '-AddendumFile', $add) $false 'Лимит отправок \(video 3\)|Резерв исправлений'
Step 'B: баланс 1220.99 − 593 = 627.99' 'ep003_balance_check.ps1' @() $true 'balance=627.99 actual=593 pending=0 images=5 \(retry 2\) videos=3 \(retry 1\)'
$cb = Calls $B
$ctB = @($cb | Where-Object call -eq 'createTask')
Check 'B: createTask 4 раза (C, K2, D, D-retry1)' ($ctB.Count -eq 4)
Check 'B: C — 6 полей без last_frame_url, first = K0' ((Keys $ctB[0].body.input) -eq 'aspect_ratio,duration,first_frame_url,generate_audio,prompt,resolution' -and $ctB[0].body.input.first_frame_url -match 'EP003_K0_')
Check 'B: D-retry1 = промпт D + правка, 6 полей без last_frame_url, 4 с, first = K2' ($ctB[3].body.input.prompt -ceq ((PlanPrompt 'D') + "`n" + $addText) -and (Keys $ctB[3].body.input) -eq 'aspect_ratio,duration,first_frame_url,generate_audio,prompt,resolution' -and $ctB[3].body.input.duration -eq 4 -and $ctB[3].body.input.first_frame_url -match 'EP003_K2_')
Check 'B: журнал ревизии 1 сохранён, старые .task.json не изменились' ((PrefixKept $B) -and (RecsUnchanged $B))

# =================== общее ===================
Check 'ключ нигде в тестовых файлах' (-not (Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.json', '*.jsonl', '*.txt' | Select-String -SimpleMatch 'FAKE-KEY' -List))
Check 'E:\Generations не изменился' ((Snap) -eq $snapBefore)
$env:EP003_TEST_GEN = $null; $env:EP003_MOCK = $null; $env:KIE_EXEC_INPUTS = $null
'ИТОГО: ' + $pass + ' PASS, ' + $failn + ' FAIL; папка ' + $root
