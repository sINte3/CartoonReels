# Сухой прогон ep002 на моках: тестовая папка во временном каталоге вместо E:\Generations, входные файлы — из git (export-inputs.ps1),
# прокси закрывает реальную сеть. Проверяет весь пакет K0 → K1 (+ retry) → A → кадр A → K2 → B → сборка 9 с / 216 кадров,
# отказ по бюджету, таймаут createTask → запрет повтора и любых новых отправок.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$prod = Split-Path $here
$repo = Split-Path (Split-Path (Split-Path $prod))
$heroSrc = Join-Path $repo 'deliverables\lookdev-02\hero-3d-keyframe.png'
$realGen = 'E:\Generations'
$root = Join-Path ([IO.Path]::GetTempPath()) ('kie-executor-ep002-dryrun_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$T = Join-Path $root 'gen'; $M = Join-Path $root 'mock'; $I = Join-Path $root 'inputs'
New-Item -ItemType Directory -Path (Join-Path $T 'refs'), $M | Out-Null
Copy-Item -LiteralPath $heroSrc -Destination (Join-Path $T 'refs')
& (Join-Path $prod 'export-inputs.ps1') -Dest $I
$add = Join-Path $root 'CartoonReels_EP002_dryrun_addendum.prompt.en.txt'
[IO.File]::WriteAllText($add, "Targeted correction for the dry run: keep both forepaws on the bar and the single tail clearly wrapped around its center.`n")
ffmpeg -v error -f lavfi -i 'testsrc2=size=1536x2752:rate=1' -frames:v 1 (Join-Path $M 'result_image.png')
ffmpeg -v error -f lavfi -i 'testsrc2=size=720x1280:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=44100' -t 4.0417 -c:v libx264 -pix_fmt yuv420p -c:a aac (Join-Path $M 'result_video4.mp4')
ffmpeg -v error -f lavfi -i 'testsrc=size=720x1280:rate=24' -f lavfi -i 'sine=frequency=220:sample_rate=44100' -t 5.0417 -c:v libx264 -pix_fmt yuv420p -c:a aac (Join-Path $M 'result_video5.mp4')
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'ok'
function Snap { if (Test-Path -LiteralPath $realGen) { $f = @(Get-ChildItem -LiteralPath $realGen -Recurse -File); '' + $f.Count + '/' + ($f | Measure-Object Length -Sum).Sum + '/' + (($f | Sort-Object LastWriteTimeUtc | Select-Object -Last 1).LastWriteTimeUtc.Ticks) } }
$snapBefore = Snap
$env:EP002_TEST_GEN = $T; $env:EP002_MOCK = $M; $env:KIE_EXEC_INPUTS = $I
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
Step 'activate' 'ep002_activate.ps1' @() $true 'Стартовый баланс: 649.99'
Step 'activate again refused' 'ep002_activate.ps1' @() $false 'уже существует'
Step 'K1 before K0 accepted refused' 'ep002_create.ps1' @('-Label', 'K1') $false 'не принят'
Step 'create K0' 'ep002_create.ps1' @('-Label', 'K0') $true 'Задача создана: K0 taskId mocktask0001 .*ожидается 12 кр'
Step 'create K0 again refused' 'ep002_create.ps1' @('-Label', 'K0') $false 'уже'
Step 'poll K0' 'ep002_poll.ps1' @('-Label', 'K0') $true 'creditsConsumed = 12'
Step 'save K0' 'ep002_save.ps1' @('-Label', 'K0') $true '"format":"png"'
Step 'save K0 again refused' 'ep002_save.ps1' @('-Label', 'K0') $false 'уже сохранён'
Step 'K0-retry1 without reject refused' 'ep002_create.ps1' @('-Label', 'K0-retry1') $false 'только после записанного отказа'
Step 'accept K0' 'ep002_decide.ps1' @('-Label', 'K0', '-Decision', 'accept', '-Reason', 'dry') $true 'accept K0'
Step 'create K1' 'ep002_create.ps1' @('-Label', 'K1') $true 'taskId mocktask0002'
Step 'poll K1' 'ep002_poll.ps1' @('-Label', 'K1') $true 'creditsConsumed = 12'
Step 'save K1' 'ep002_save.ps1' @('-Label', 'K1') $true 'png'
Step 'reject K1' 'ep002_decide.ps1' @('-Label', 'K1', '-Decision', 'reject', '-Reason', 'dry defect') $true 'reject K1'
Step 'A before K1 accepted refused' 'ep002_create.ps1' @('-Label', 'A') $false 'не принят'
Step 'addendum on base attempt refused' 'ep002_create.ps1' @('-Label', 'A', '-AddendumFile', $add) $false 'только для адресного повтора'
Step 'create K1-retry1' 'ep002_create.ps1' @('-Label', 'K1-retry1', '-AddendumFile', $add) $true 'taskId mocktask0003'
Step 'poll K1-retry1' 'ep002_poll.ps1' @('-Label', 'K1-retry1') $true 'creditsConsumed = 12'
Step 'save K1-retry1' 'ep002_save.ps1' @('-Label', 'K1-retry1') $true 'png'
Step 'accept K1-retry1' 'ep002_decide.ps1' @('-Label', 'K1-retry1', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'create A (4 s)' 'ep002_create.ps1' @('-Label', 'A') $true 'taskId mocktask0004 .*ожидается 164 кр'
Step 'poll A' 'ep002_poll.ps1' @('-Label', 'A') $true 'creditsConsumed = 164'
Step 'save A' 'ep002_save.ps1' @('-Label', 'A') $true '"audio":true'
Step 'K2 before A accepted refused' 'ep002_create.ps1' @('-Label', 'K2') $false 'не принят'
Step 'accept A' 'ep002_decide.ps1' @('-Label', 'A', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'K2 before alast refused' 'ep002_create.ps1' @('-Label', 'K2') $false 'Нет извлечённого'
Step 'alast (frame 95 of 96)' 'ep002_alast.ps1' @() $true '720,1280.*сверен'
Step 'alast again refused' 'ep002_alast.ps1' @() $false 'уже извлечён'
Step 'create K2' 'ep002_create.ps1' @('-Label', 'K2') $true 'taskId mocktask0005'
Step 'poll K2' 'ep002_poll.ps1' @('-Label', 'K2') $true 'creditsConsumed = 12'
Step 'save K2' 'ep002_save.ps1' @('-Label', 'K2') $true 'png'
Step 'accept K2' 'ep002_decide.ps1' @('-Label', 'K2', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'assemble before B refused' 'ep002_assemble.ps1' @() $false 'не принят'
Step 'create B (5 s)' 'ep002_create.ps1' @('-Label', 'B') $true 'taskId mocktask0006 .*ожидается 205 кр'
Step 'poll B' 'ep002_poll.ps1' @('-Label', 'B') $true 'creditsConsumed = 205'
Step 'save B' 'ep002_save.ps1' @('-Label', 'B') $true '"audio":true'
Step 'accept B' 'ep002_decide.ps1' @('-Label', 'B', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'balance check 649.99 - 417 = 232.99' 'ep002_balance_check.ps1' @() $true 'balance=232.99 actual=417 pending=0 images=4 \(retry 1\) videos=2 \(retry 0\)'
Step 'assemble -MeasureOnly' 'ep002_assemble.ps1' @('-MeasureOnly') $true 'loud_0_5s'
Step 'assemble 9 s / 216 frames' 'ep002_assemble.ps1' @('-GainB', '1.5') $true '"frames_216": true'
Step 'reject A after assembly (test only)' 'ep002_decide.ps1' @('-Label', 'A', '-Decision', 'reject', '-Reason', 'dry budget test') $true 'reject A'
Step 'A-retry1 over cap refused (417 + 164 + 217 > 640)' 'ep002_create.ps1' @('-Label', 'A-retry1', '-AddendumFile', $add) $false 'Бюджет: .*798 > 640'
Step 're-accept A (test only)' 'ep002_decide.ps1' @('-Label', 'A', '-Decision', 'accept', '-Reason', 'dry') $true 'accept A'
Step 'reject B (test only)' 'ep002_decide.ps1' @('-Label', 'B', '-Decision', 'reject', '-Reason', 'dry timeout test') $true 'reject B'
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'timeout'
Step 'create B-retry1 with createTask timeout -> unknown, stop' 'ep002_create.ps1' @('-Label', 'B-retry1', '-AddendumFile', $add) $false 'НЕ повторять'
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'ok'
Step 'B-retry1 again refused (record exists)' 'ep002_create.ps1' @('-Label', 'B-retry1', '-AddendumFile', $add) $false 'уже'
Step 'reject K2 (test only)' 'ep002_decide.ps1' @('-Label', 'K2', '-Decision', 'reject', '-Reason', 'dry') $true 'reject K2'
Step 'any new create refused while unknown open' 'ep002_create.ps1' @('-Label', 'K2-retry1', '-AddendumFile', $add) $false 'невыясненная'
Step 'poll unknown B-retry1 refuses (no taskId)' 'ep002_poll.ps1' @('-Label', 'B-retry1') $false 'нет корректного taskId'

# ---------- проверки содержимого ----------
$calls = @(Get-Content -LiteralPath (Join-Path $M 'calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
$ct = @($calls | Where-Object call -eq 'createTask')
$ups = @($calls | Where-Object call -eq 'upload')
$plan = Get-Content -Raw -LiteralPath (Join-Path $I 'plan.json') | ConvertFrom-Json -AsHashtable
function PlanPrompt([string]$id) { (@(@($plan.image_tasks) + @($plan.video_tasks) | Where-Object { $_.id -eq $id }))[0].request_template.input.prompt }
$addText = [IO.File]::ReadAllText($add).TrimEnd("`r", "`n")
$inv = [Globalization.CultureInfo]::InvariantCulture
function Ssim([string]$a, [string]$b) { $o = (ffmpeg -hide_banner -nostats -i $a -i $b -lavfi '[0:v]format=yuv420p[x];[1:v]format=yuv420p[y];[x][y]ssim' -f null - 2>&1 | Out-String); if ($o -match 'All:([\d.]+)') { [double]::Parse($Matches[1], $inv) } else { -1 } }
function FrameAt([string]$f, [int]$n, [string]$chain, [string]$out) { ffmpeg -v error -y -i $f -vf ($chain + ',select=eq(n\,' + $n + ')') -frames:v 1 -fps_mode passthrough $out; $out }
$out720 = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP002_9s_sound_720p_*.mp4')[0].FullName
$out1080 = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP002_9s_sound_1080p_*.mp4')[0].FullName
function Pr([string]$f) { (ffprobe -v error -count_frames -show_entries 'stream=codec_type,codec_name,width,height,r_frame_rate,nb_read_frames,sample_rate,channels,duration' -of json $f | Out-String) | ConvertFrom-Json }
$p720 = Pr $out720; $p1080 = Pr $out1080
$v720 = @($p720.streams | Where-Object codec_type -eq 'video')[0]; $a720 = @($p720.streams | Where-Object codec_type -eq 'audio')[0]
$v1080 = @($p1080.streams | Where-Object codec_type -eq 'video')[0]
$alast = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP002_A-lastframe_*.png')[0].FullName
$aMp4 = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP002_A_*.mp4')[0].FullName
$bMp4 = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP002_B_*.mp4')[0].FullName
$f95 = FrameAt $out720 95 'null' (Join-Path $root 'out_f95.png')
$f96 = FrameAt $out720 96 'null' (Join-Path $root 'out_f96.png')
$f170 = FrameAt $out720 170 'null' (Join-Path $root 'out_f170.png')
$b0 = FrameAt $bMp4 0 'fps=24' (Join-Path $root 'b_f0.png')
$b74 = FrameAt $bMp4 74 'fps=24' (Join-Path $root 'b_f74.png')
$gainFile = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP002_assemble-with-audio.gain_*.ffmpeg.txt')
$chk = @(
  @('createTask отправлен 7 раз (K0, K1, K1-retry1, A, K2, B, B-retry1-timeout); A-retry1 сверх лимита не отправлен', ($ct.Count -eq 7)),
  @('все createTask с ключом из Set-Key', (@($ct | Where-Object { -not $_.authOk }).Count -eq 0)),
  @('все загрузки в uploadPath cartoonreels/ep002 с ключом', (@($ups | Where-Object { $_.uploadPath -ne 'cartoonreels/ep002' -or -not $_.authHeader }).Count -eq 0 -and $ups.Count -eq 14)),
  @('K0: nano-banana-2, 1 референс (hero), 2K 9:16 png, промпт = plan.json', ($ct[0].body.model -eq 'nano-banana-2' -and @($ct[0].body.input.image_input).Count -eq 1 -and $ct[0].body.input.image_input[0] -match 'hero-3d-keyframe' -and $ct[0].body.input.resolution -eq '2K' -and $ct[0].body.input.aspect_ratio -eq '9:16' -and $ct[0].body.input.output_format -eq 'png' -and $ct[0].body.input.prompt -ceq (PlanPrompt 'K0'))),
  @('K1: 2 референса (K0, hero), промпт = plan.json', (@($ct[1].body.input.image_input).Count -eq 2 -and $ct[1].body.input.image_input[0] -match 'CartoonReels_EP002_K0_' -and $ct[1].body.input.image_input[1] -match 'hero-3d-keyframe' -and $ct[1].body.input.prompt -ceq (PlanPrompt 'K1'))),
  @('K1-retry1 = промпт K1 + перевод строки + правка, 2 референса', (($ct[2].body.input.prompt -ceq ((PlanPrompt 'K1') + "`n" + $addText)) -and @($ct[2].body.input.image_input).Count -eq 2)),
  @('A: seedance-2, first K0, last K1-retry1, duration 4 целым, 720p, 9:16, звук true, без reference_*, промпт = plan.json', ($ct[3].body.model -eq 'bytedance/seedance-2' -and $ct[3].body.input.first_frame_url -match 'EP002_K0_' -and $ct[3].body.input.last_frame_url -match 'EP002_K1-retry1_' -and $ct[3].body.input.duration -is [long] -and $ct[3].body.input.duration -eq 4 -and $ct[3].body.input.resolution -eq '720p' -and $ct[3].body.input.aspect_ratio -eq '9:16' -and $ct[3].body.input.generate_audio -eq $true -and -not (@($ct[3].body.input.Keys) -match '^reference_') -and $ct[3].body.input.prompt -ceq (PlanPrompt 'A'))),
  @('K2: 3 референса (A-last, K0, hero), промпт = plan.json', (@($ct[4].body.input.image_input).Count -eq 3 -and $ct[4].body.input.image_input[0] -match 'A-lastframe' -and $ct[4].body.input.image_input[1] -match 'EP002_K0_' -and $ct[4].body.input.image_input[2] -match 'hero' -and $ct[4].body.input.prompt -ceq (PlanPrompt 'K2'))),
  @('B: first A-last, last K2, duration 5 целым, 720p, 9:16, звук true, без reference_*, промпт = plan.json', ($ct[5].body.model -eq 'bytedance/seedance-2' -and $ct[5].body.input.first_frame_url -match 'A-lastframe' -and $ct[5].body.input.last_frame_url -match 'EP002_K2_' -and $ct[5].body.input.duration -is [long] -and $ct[5].body.input.duration -eq 5 -and $ct[5].body.input.resolution -eq '720p' -and $ct[5].body.input.generate_audio -eq $true -and -not (@($ct[5].body.input.Keys) -match '^reference_') -and $ct[5].body.input.prompt -ceq (PlanPrompt 'B'))),
  @('B-retry1 = промпт B + правка, duration 5', ($ct[6].body.input.prompt -ceq ((PlanPrompt 'B') + "`n" + $addText) -and $ct[6].body.input.duration -eq 5)),
  @('720p: 720×1280, 24/1, 216 кадров, AAC 48 кГц стерео, аудио 9 с', ([int]$v720.width -eq 720 -and [int]$v720.height -eq 1280 -and $v720.r_frame_rate -eq '24/1' -and [int]$v720.nb_read_frames -eq 216 -and $a720.codec_name -eq 'aac' -and $a720.sample_rate -eq '48000' -and [int]$a720.channels -eq 2 -and [Math]::Abs([double]::Parse($a720.duration, $inv) - 9.0) -lt 0.05)),
  @('1080p: 1080×1920, 216 кадров', ([int]$v1080.width -eq 1080 -and [int]$v1080.height -eq 1920 -and [int]$v1080.nb_read_frames -eq 216)),
  @('кадр 95 монтажа ≈ извлечённый последний кадр A (SSIM > 0.95)', ((Ssim $f95 $alast) -gt 0.95)),
  @('кадр 96 монтажа ≈ первый кадр B (SSIM > 0.95) — склейка 96/120', ((Ssim $f96 $b0) -gt 0.95)),
  @('кадр 170 монтажа ≈ кадр 74 B без укрупнения (SSIM > 0.95)', ((Ssim $f170 $b74) -gt 0.95)),
  @('фильтр с усилением: volume=1.5dB только в цепочке [1:a]', ($gainFile.Count -eq 1 -and (Get-Content -LiteralPath $gainFile[0].FullName | Where-Object { $_ -match 'volume=' }) -join '' -match '^\[1:a\].*volume=1\.5dB')),
  @('ключ нигде в тестовых файлах', (-not (Get-ChildItem -LiteralPath $T -Recurse -File | Select-String -SimpleMatch 'FAKE-KEY' -List))),
  @('E:\Generations не изменился', ((Snap) -eq $snapBefore))
)
foreach ($c in $chk) { if ($c[1]) { $pass++; 'PASS ' + $c[0] } else { $failn++; 'FAIL ' + $c[0] } }
$env:EP002_TEST_GEN = $null; $env:EP002_MOCK = $null; $env:KIE_EXEC_INPUTS = $null
'--- журнал теста (типы): ' + ((Get-Content -LiteralPath (Get-ChildItem -LiteralPath $T -Filter '*journal*').FullName | ForEach-Object { ($_ | ConvertFrom-Json).type }) -join ', ')
'ИТОГО: ' + $pass + ' PASS, ' + $failn + ' FAIL; папка ' + $root
