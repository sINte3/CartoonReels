# ИСТОРИЧЕСКИЙ: сухой прогон ревизии 1 (граф с K1, C first+last), 85 PASS / 0 FAIL 09.11.2026 на коммите 6d49f51.
# С исполнителем ревизии 2 не запускается (активация закрыта, K1 исключён) — для неё run_continue_dry.ps1.
# Сухой прогон ep003 на моках: тестовая папка во временном каталоге вместо E:\Generations, поддельный ключ, входные файлы — из git
# (export-inputs.ps1, включая готовое начало и его кадр 167), прокси закрывает реальную сеть.
# Проверяет: смену тарифа и нехватку средств до активации; пакет K0 → K1 (+ retry) → C → кадр 119 C → K2 (+ retry) → D → сборка 16 с / 384 кадра;
# тела C (first+last) и D (только first, без поля last_frame_url); лимиты 5/3; бюджет 634; запрет перекрывающихся и повторных отправок;
# продолжение опроса после остановки; таймаут createTask → запрет повтора и любых новых отправок.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$prod = Split-Path $here
$repo = Split-Path (Split-Path (Split-Path $prod))
$heroSrc = Join-Path $repo 'deliverables\lookdev-02\hero-3d-keyframe.png'
$realGen = 'E:\Generations'
$root = Join-Path ([IO.Path]::GetTempPath()) ('kie-executor-ep003-dryrun_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$T = Join-Path $root 'gen'; $M = Join-Path $root 'mock'; $I = Join-Path $root 'inputs'
New-Item -ItemType Directory -Path (Join-Path $T 'refs'), $M | Out-Null
Copy-Item -LiteralPath $heroSrc -Destination (Join-Path $T 'refs')
& (Join-Path $prod 'export-inputs.ps1') -Dest $I
$add = Join-Path $root 'CartoonReels_EP003_dryrun_addendum.prompt.en.txt'
[IO.File]::WriteAllText($add, "Targeted correction for the dry run: keep both forepaws holding the medal far above the bar and the single tail as the only support.`n")
ffmpeg -v error -f lavfi -i 'testsrc2=size=1536x2752:rate=1' -frames:v 1 (Join-Path $M 'result_image.png')
ffmpeg -v error -f lavfi -i 'testsrc2=size=720x1280:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=44100' -t 4.0417 -c:v libx264 -pix_fmt yuv420p -c:a aac (Join-Path $M 'result_video4.mp4')
ffmpeg -v error -f lavfi -i 'testsrc=size=720x1280:rate=24' -f lavfi -i 'sine=frequency=220:sample_rate=44100' -t 5.0417 -c:v libx264 -pix_fmt yuv420p -c:a aac (Join-Path $M 'result_video5.mp4')
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'ok'
function Snap { if (Test-Path -LiteralPath $realGen) { $f = @(Get-ChildItem -LiteralPath $realGen -Recurse -File); '' + $f.Count + '/' + ($f | Measure-Object Length -Sum).Sum + '/' + (($f | Sort-Object LastWriteTimeUtc | Select-Object -Last 1).LastWriteTimeUtc.Ticks) } }
$snapBefore = Snap
$env:EP003_TEST_GEN = $T; $env:EP003_MOCK = $M; $env:KIE_EXEC_INPUTS = $I
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
function NoJournal { -not (Get-ChildItem -LiteralPath $T -Filter '*journal*' -File) }

# ---------- до активации: тариф и деньги ----------
Set-Content -LiteralPath (Join-Path $M 'nbprice.txt') -Value '13'
Step 'activation refused on changed tariff' 'ep003_activate.ps1' @() $false 'Тариф изменился'
Remove-Item -LiteralPath (Join-Path $M 'nbprice.txt')
@{ balance = 300.0; n = 0; tasks = @{}; charged = @{} } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $M 'state.json') -Encoding utf8
Step 'activation refused on low balance (300 < 405, short 105)' 'ep003_activate.ps1' @() $false 'не хватает 105 кр'
Remove-Item -LiteralPath (Join-Path $M 'state.json')
$noJ = NoJournal
Step 'create before activation refused' 'ep003_create.ps1' @('-Label', 'K0') $false 'Журнал пакета: найдено 0'

# ---------- основной пакет ----------
Step 'activate' 'ep003_activate.ps1' @() $true 'Стартовый баланс: 1220.99'
Step 'activate again refused' 'ep003_activate.ps1' @() $false 'уже существует'
Step 'K1 before K0 accepted refused' 'ep003_create.ps1' @('-Label', 'K1') $false 'не принят'
Step 'create K0' 'ep003_create.ps1' @('-Label', 'K0') $true 'Задача создана: K0 taskId mocktask0001 .*ожидается 12 кр.*"remainingMandatoryAfter":393.*"projectedMax":405'
Step 'create K0 again refused (taskId known)' 'ep003_create.ps1' @('-Label', 'K0') $false 'уже'
Step 'overlapping create K1 refused while K0 not polled' 'ep003_create.ps1' @('-Label', 'K1') $false 'невыясненная'
Step 'poll K0' 'ep003_poll.ps1' @('-Label', 'K0') $true 'creditsConsumed = 12'
Step 'save K0' 'ep003_save.ps1' @('-Label', 'K0') $true '"format":"png"'
Step 'save K0 again refused' 'ep003_save.ps1' @('-Label', 'K0') $false 'уже сохранён'
Step 'K0-retry1 without reject refused' 'ep003_create.ps1' @('-Label', 'K0-retry1') $false 'только после записанного отказа'
Step 'accept K0' 'ep003_decide.ps1' @('-Label', 'K0', '-Decision', 'accept', '-Reason', 'dry') $true 'accept K0'
Step 'create K1' 'ep003_create.ps1' @('-Label', 'K1') $true 'taskId mocktask0002 .*"remainingMandatoryAfter":381'
Step 'poll K1' 'ep003_poll.ps1' @('-Label', 'K1') $true 'creditsConsumed = 12'
Step 'save K1' 'ep003_save.ps1' @('-Label', 'K1') $true 'png'
Step 'reject K1' 'ep003_decide.ps1' @('-Label', 'K1', '-Decision', 'reject', '-Reason', 'dry defect: paw touches bar') $true 'reject K1'
Step 'C before K1 accepted refused' 'ep003_create.ps1' @('-Label', 'C') $false 'не принят'
Step 'addendum on base attempt refused' 'ep003_create.ps1' @('-Label', 'C', '-AddendumFile', $add) $false 'только для адресного повтора'
Step 'create K1-retry1' 'ep003_create.ps1' @('-Label', 'K1-retry1', '-AddendumFile', $add) $true 'taskId mocktask0003'
Step 'poll K1-retry1' 'ep003_poll.ps1' @('-Label', 'K1-retry1') $true 'creditsConsumed = 12'
Step 'save K1-retry1' 'ep003_save.ps1' @('-Label', 'K1-retry1') $true 'png'
Step 'accept K1-retry1' 'ep003_decide.ps1' @('-Label', 'K1-retry1', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'create C (5 s, first+last)' 'ep003_create.ps1' @('-Label', 'C') $true 'taskId mocktask0004 .*ожидается 205 кр.*"remainingMandatoryAfter":176'
Step 'poll C' 'ep003_poll.ps1' @('-Label', 'C') $true 'creditsConsumed = 205'
Step 'save C' 'ep003_save.ps1' @('-Label', 'C') $true '"audio":true'
Step 'K2 before C accepted refused' 'ep003_create.ps1' @('-Label', 'K2') $false 'не принят'
Step 'clast before C accepted refused' 'ep003_clast.ps1' @() $false 'C не принят'
Step 'accept C' 'ep003_decide.ps1' @('-Label', 'C', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'K2 before C last frame refused' 'ep003_create.ps1' @('-Label', 'K2') $false 'Нет извлечённого'
Step 'clast (frame 119 of 120)' 'ep003_clast.ps1' @() $true '720,1280.*кадр 119 сверен'
Step 'clast again refused' 'ep003_clast.ps1' @() $false 'уже извлечён'
Step 'D before K2 accepted refused' 'ep003_create.ps1' @('-Label', 'D') $false 'не принят'
Step 'create K2' 'ep003_create.ps1' @('-Label', 'K2') $true 'taskId mocktask0005 .*"remainingMandatoryAfter":164'
Step 'poll K2' 'ep003_poll.ps1' @('-Label', 'K2') $true 'creditsConsumed = 12'
Step 'save K2' 'ep003_save.ps1' @('-Label', 'K2') $true 'png'
Step 'reject K2' 'ep003_decide.ps1' @('-Label', 'K2', '-Decision', 'reject', '-Reason', 'dry defect: medal still in paws') $true 'reject K2'
Step 'create K2-retry1' 'ep003_create.ps1' @('-Label', 'K2-retry1', '-AddendumFile', $add) $true 'taskId mocktask0006'
Step 'poll K2-retry1' 'ep003_poll.ps1' @('-Label', 'K2-retry1') $true 'creditsConsumed = 12'
Step 'save K2-retry1' 'ep003_save.ps1' @('-Label', 'K2-retry1') $true 'png'
Step 'reject K2-retry1 (test only)' 'ep003_decide.ps1' @('-Label', 'K2-retry1', '-Decision', 'reject', '-Reason', 'dry limit test') $true 'reject'
Step 'K2-retry2 refused: image limit 5' 'ep003_create.ps1' @('-Label', 'K2-retry2', '-AddendumFile', $add) $false 'Лимит отправок \(image 5\)'
Step 're-accept K2-retry1' 'ep003_decide.ps1' @('-Label', 'K2-retry1', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'assemble before D refused' 'ep003_assemble.ps1' @() $false 'не принят'
Step 'create D (4 s, first only)' 'ep003_create.ps1' @('-Label', 'D') $true 'taskId mocktask0007 .*ожидается 164 кр.*"remainingMandatoryAfter":0'
Step 'create D again refused (taskId known)' 'ep003_create.ps1' @('-Label', 'D') $false 'уже'
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'pollslow'
Step 'poll D stops while generating' 'ep003_poll.ps1' @('-Label', 'D', '-Minutes', '0') $true 'Ещё идёт: D taskId mocktask0007, state = generating'
Step 'balance check with D in flight (pending 164)' 'ep003_balance_check.ps1' @() $true 'actual=265 pending=164'
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'ok'
Step 'poll D resumes by saved taskId' 'ep003_poll.ps1' @('-Label', 'D') $true 'creditsConsumed = 164'
Step 'save D' 'ep003_save.ps1' @('-Label', 'D') $true '"audio":true'
Step 'accept D' 'ep003_decide.ps1' @('-Label', 'D', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'balance check 1220.99 - 429 = 791.99' 'ep003_balance_check.ps1' @() $true 'balance=791.99 actual=429 pending=0 images=5 \(retry 2\) videos=2 \(retry 0\)'
Step 'assemble -MeasureOnly' 'ep003_assemble.ps1' @('-MeasureOnly') $true 'loud_used'
Step 'assemble 16 s / 384 frames' 'ep003_assemble.ps1' @('-GainC', '1.5') $true '"frames_384": true'
Step 'reject C after assembly (test only)' 'ep003_decide.ps1' @('-Label', 'C', '-Decision', 'reject', '-Reason', 'dry budget test') $true 'reject C'
Step 'C-retry1 over cap refused (429 + 205 + 176 > 634)' 'ep003_create.ps1' @('-Label', 'C-retry1', '-AddendumFile', $add) $false 'Бюджет: .*810 > 634'
Step 're-accept C (test only)' 'ep003_decide.ps1' @('-Label', 'C', '-Decision', 'accept', '-Reason', 'dry') $true 'accept C'
Step 'reject D (test only)' 'ep003_decide.ps1' @('-Label', 'D', '-Decision', 'reject', '-Reason', 'dry timeout test') $true 'reject D'
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'timeout'
Step 'create D-retry1 with createTask timeout -> unknown, stop' 'ep003_create.ps1' @('-Label', 'D-retry1', '-AddendumFile', $add) $false 'НЕ повторять'
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'ok'
Step 'D-retry1 again refused (record exists)' 'ep003_create.ps1' @('-Label', 'D-retry1', '-AddendumFile', $add) $false 'уже'
Step 'reject K2-retry1 (test only)' 'ep003_decide.ps1' @('-Label', 'K2-retry1', '-Decision', 'reject', '-Reason', 'dry') $true 'reject'
Step 'any new create refused while unknown open' 'ep003_create.ps1' @('-Label', 'K2-retry2', '-AddendumFile', $add) $false 'невыясненная'
Step 'poll unknown D-retry1 refuses (no taskId)' 'ep003_poll.ps1' @('-Label', 'D-retry1') $false 'нет корректного taskId'

# ---------- проверки содержимого ----------
$calls = @(Get-Content -LiteralPath (Join-Path $M 'calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
$ct = @($calls | Where-Object call -eq 'createTask')
$ups = @($calls | Where-Object call -eq 'upload')
$plan = Get-Content -Raw -LiteralPath (Join-Path $I 'plan.json') | ConvertFrom-Json -AsHashtable
function PlanPrompt([string]$id) { (@(@($plan.image_tasks) + @($plan.video_tasks) | Where-Object { $_.id -eq $id }))[0].request_template.input.prompt }
function Keys($h) { (@($h.Keys) | Sort-Object) -join ',' }
$addText = [IO.File]::ReadAllText($add).TrimEnd("`r", "`n")
$inv = [Globalization.CultureInfo]::InvariantCulture
function Ssim([string]$a, [string]$b) { $o = (ffmpeg -hide_banner -nostats -i $a -i $b -lavfi '[0:v]format=yuv420p[x];[1:v]format=yuv420p[y];[x][y]ssim' -f null - 2>&1 | Out-String); if ($o -match 'All:([\d.]+)') { [double]::Parse($Matches[1], $inv) } else { -1 } }
function FrameAt([string]$f, [int]$n, [string]$chain, [string]$out) { ffmpeg -v error -y -i $f -vf ($chain + ',select=eq(n\,' + $n + ')') -frames:v 1 -fps_mode passthrough $out; $out }
$out720 = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP003_16s_sound_720p_*.mp4')[0].FullName
$out1080 = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP003_16s_sound_1080p_*.mp4')[0].FullName
function Pr([string]$f) { (ffprobe -v error -count_frames -show_entries 'stream=codec_type,codec_name,width,height,r_frame_rate,nb_read_frames,sample_rate,channels,duration' -of json $f | Out-String) | ConvertFrom-Json }
$p720 = Pr $out720; $p1080 = Pr $out1080
$v720 = @($p720.streams | Where-Object codec_type -eq 'video')[0]; $a720 = @($p720.streams | Where-Object codec_type -eq 'audio')[0]
$v1080 = @($p1080.streams | Where-Object codec_type -eq 'video')[0]
$clast = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP003_C-lastframe_*.png')[0].FullName
$cMp4 = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP003_C_*.mp4')[0].FullName
$dMp4 = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP003_D_*.mp4')[0].FullName
$f167 = FrameAt $out720 167 'null' (Join-Path $root 'out_f167.png')
$f168 = FrameAt $out720 168 'null' (Join-Path $root 'out_f168.png')
$f287 = FrameAt $out720 287 'null' (Join-Path $root 'out_f287.png')
$f288 = FrameAt $out720 288 'null' (Join-Path $root 'out_f288.png')
$f330 = FrameAt $out720 330 'null' (Join-Path $root 'out_f330.png')
$c0 = FrameAt $cMp4 0 'fps=24' (Join-Path $root 'c_f0.png')
$d0 = FrameAt $dMp4 0 'fps=24' (Join-Path $root 'd_f0.png')
$d42 = FrameAt $dMp4 42 'fps=24' (Join-Path $root 'd_f42.png')
$gainFile = @(Get-ChildItem -LiteralPath $T -Filter 'CartoonReels_EP003_assemble-with-audio.gain_*.ffmpeg.txt')
$byLbl = @{ K0 = $ct[0]; K1 = $ct[1]; K1r = $ct[2]; C = $ct[3]; K2 = $ct[4]; K2r = $ct[5]; D = $ct[6]; Dr = $ct[7] }
$chk = @(
  @('до активации: при смене тарифа и нехватке денег журнал не создан и createTask не было', ($noJ -and @($calls | Select-Object -First 4 | Where-Object call -eq 'createTask').Count -eq 0)),
  @('createTask отправлен 8 раз (K0, K1, K1-retry1, C, K2, K2-retry1, D, D-retry1-timeout); K2-retry2 и C-retry1 не отправлены', ($ct.Count -eq 8)),
  @('все createTask с ключом из Set-Key', (@($ct | Where-Object { -not $_.authOk }).Count -eq 0)),
  @('18 загрузок, все в uploadPath cartoonreels/ep003 с ключом', (@($ups | Where-Object { $_.uploadPath -ne 'cartoonreels/ep003' -or -not $_.authHeader }).Count -eq 0 -and $ups.Count -eq 18)),
  @('K0: nano-banana-2, 2 референса (кадр 167 начала, герой), 2K 9:16 png, промпт = plan.json', ($byLbl.K0.body.model -eq 'nano-banana-2' -and @($byLbl.K0.body.input.image_input).Count -eq 2 -and $byLbl.K0.body.input.image_input[0] -match 'opening-lastframe' -and $byLbl.K0.body.input.image_input[1] -match 'hero-3d-keyframe' -and $byLbl.K0.body.input.resolution -eq '2K' -and $byLbl.K0.body.input.aspect_ratio -eq '9:16' -and $byLbl.K0.body.input.output_format -eq 'png' -and $byLbl.K0.body.input.prompt -ceq (PlanPrompt 'K0'))),
  @('K1: 3 референса (K0, кадр 167 начала, герой), промпт = plan.json', (@($byLbl.K1.body.input.image_input).Count -eq 3 -and $byLbl.K1.body.input.image_input[0] -match 'CartoonReels_EP003_K0_' -and $byLbl.K1.body.input.image_input[1] -match 'opening-lastframe' -and $byLbl.K1.body.input.image_input[2] -match 'hero-3d-keyframe' -and $byLbl.K1.body.input.prompt -ceq (PlanPrompt 'K1'))),
  @('K1-retry1 = промпт K1 + перевод строки + правка, 3 референса', (($byLbl.K1r.body.input.prompt -ceq ((PlanPrompt 'K1') + "`n" + $addText)) -and @($byLbl.K1r.body.input.image_input).Count -eq 3)),
  @('C: seedance-2, ровно 7 полей, first K0, last K1-retry1, duration 5 целым, 720p, 9:16, звук true, без reference_*, промпт = plan.json', ($byLbl.C.body.model -eq 'bytedance/seedance-2' -and (Keys $byLbl.C.body.input) -eq 'aspect_ratio,duration,first_frame_url,generate_audio,last_frame_url,prompt,resolution' -and $byLbl.C.body.input.first_frame_url -match 'EP003_K0_' -and $byLbl.C.body.input.last_frame_url -match 'EP003_K1-retry1_' -and $byLbl.C.body.input.duration -is [long] -and $byLbl.C.body.input.duration -eq 5 -and $byLbl.C.body.input.resolution -eq '720p' -and $byLbl.C.body.input.aspect_ratio -eq '9:16' -and $byLbl.C.body.input.generate_audio -eq $true -and $byLbl.C.body.input.prompt -ceq (PlanPrompt 'C'))),
  @('K2: 3 референса (кадр 119 C, K0, герой), промпт = plan.json', (@($byLbl.K2.body.input.image_input).Count -eq 3 -and $byLbl.K2.body.input.image_input[0] -match 'C-lastframe' -and $byLbl.K2.body.input.image_input[1] -match 'EP003_K0_' -and $byLbl.K2.body.input.image_input[2] -match 'hero' -and $byLbl.K2.body.input.prompt -ceq (PlanPrompt 'K2'))),
  @('D: ровно 6 полей, first K2-retry1, поля last_frame_url нет совсем, duration 4 целым, 720p, 9:16, звук true, без reference_*, промпт = plan.json', ($byLbl.D.body.model -eq 'bytedance/seedance-2' -and (Keys $byLbl.D.body.input) -eq 'aspect_ratio,duration,first_frame_url,generate_audio,prompt,resolution' -and -not $byLbl.D.body.input.ContainsKey('last_frame_url') -and $byLbl.D.body.input.first_frame_url -match 'EP003_K2-retry1_' -and $byLbl.D.body.input.duration -is [long] -and $byLbl.D.body.input.duration -eq 4 -and $byLbl.D.body.input.resolution -eq '720p' -and $byLbl.D.body.input.generate_audio -eq $true -and $byLbl.D.body.input.prompt -ceq (PlanPrompt 'D'))),
  @('D-retry1 = промпт D + правка, duration 4, без last_frame_url', ($byLbl.Dr.body.input.prompt -ceq ((PlanPrompt 'D') + "`n" + $addText) -and $byLbl.Dr.body.input.duration -eq 4 -and -not $byLbl.Dr.body.input.ContainsKey('last_frame_url'))),
  @('720p: 720×1280, 24/1, 384 кадра, AAC 48 кГц стерео, аудио 16 с', ([int]$v720.width -eq 720 -and [int]$v720.height -eq 1280 -and $v720.r_frame_rate -eq '24/1' -and [int]$v720.nb_read_frames -eq 384 -and $a720.codec_name -eq 'aac' -and $a720.sample_rate -eq '48000' -and [int]$a720.channels -eq 2 -and [Math]::Abs([double]::Parse($a720.duration, $inv) - 16.0) -lt 0.05)),
  @('1080p: 1080×1920, 384 кадра', ([int]$v1080.width -eq 1080 -and [int]$v1080.height -eq 1920 -and [int]$v1080.nb_read_frames -eq 384)),
  @('кадр 167 монтажа ≈ кадр 167 начала (opening-lastframe.png, SSIM > 0.95)', ((Ssim $f167 (Join-Path $I 'opening-lastframe.png')) -gt 0.95)),
  @('кадр 168 монтажа ≈ первый кадр C (SSIM > 0.95) — склейка 168/120', ((Ssim $f168 $c0) -gt 0.95)),
  @('кадр 287 монтажа ≈ извлечённый кадр 119 C (SSIM > 0.95)', ((Ssim $f287 $clast) -gt 0.95)),
  @('кадр 288 монтажа ≈ первый кадр D (SSIM > 0.95) — склейка 288/96', ((Ssim $f288 $d0) -gt 0.95)),
  @('кадр 330 монтажа ≈ кадр 42 D без укрупнения (SSIM > 0.95)', ((Ssim $f330 $d42) -gt 0.95)),
  @('фильтр с усилением: volume=1.5dB только в цепочке [1:a], звук начала [0:a] без изменений', ($gainFile.Count -eq 1 -and ((Get-Content -LiteralPath $gainFile[0].FullName | Where-Object { $_ -match 'volume=' }) -join '') -match '^\[1:a\].*volume=1\.5dB' -and @(Get-Content -LiteralPath $gainFile[0].FullName | Where-Object { $_ -match 'volume=' }).Count -eq 1)),
  @('ключ нигде в тестовых файлах', (-not (Get-ChildItem -LiteralPath $T -Recurse -File | Select-String -SimpleMatch 'FAKE-KEY' -List))),
  @('E:\Generations не изменился', ((Snap) -eq $snapBefore))
)
foreach ($c in $chk) { if ($c[1]) { $pass++; 'PASS ' + $c[0] } else { $failn++; 'FAIL ' + $c[0] } }
$env:EP003_TEST_GEN = $null; $env:EP003_MOCK = $null; $env:KIE_EXEC_INPUTS = $null
'--- журнал теста (типы): ' + ((Get-Content -LiteralPath (Get-ChildItem -LiteralPath $T -Filter '*journal*').FullName | ForEach-Object { ($_ | ConvertFrom-Json).type }) -join ', ')
'ИТОГО: ' + $pass + ' PASS, ' + $failn + ' FAIL; папка ' + $root
