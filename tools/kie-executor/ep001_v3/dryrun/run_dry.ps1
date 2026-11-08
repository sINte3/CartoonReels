# Сухой прогон ep001_v3 на моках: тестовая папка во временном каталоге вместо E:\Generations, входные файлы — из git (export-inputs.ps1), прокси закрывает реальную сеть.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$prod = Split-Path $here
$repo = Split-Path (Split-Path (Split-Path $prod))
$heroSrc = Join-Path $repo 'deliverables\lookdev-02\hero-3d-keyframe.png'
$addK1 = Join-Path $repo 'episodes\EP001_V3\production\CartoonReels_EP001_V3_K1-retry1_addendum.prompt.en.txt'
$realGen = 'E:\Generations'
$root = Join-Path ([IO.Path]::GetTempPath()) ('kie-executor-dryrun_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$T = Join-Path $root 'gen'; $M = Join-Path $root 'mock'; $I = Join-Path $root 'inputs'
New-Item -ItemType Directory -Path (Join-Path $T 'refs'), $M | Out-Null
Copy-Item -LiteralPath $heroSrc -Destination (Join-Path $T 'refs')
& (Join-Path $prod 'export-inputs.ps1') -Dest $I
ffmpeg -v error -f lavfi -i 'testsrc2=size=1536x2752:rate=1' -frames:v 1 (Join-Path $M 'result_image.png')
ffmpeg -v error -f lavfi -i 'testsrc2=size=720x1280:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=44100' -t 4.0417 -c:v libx264 -pix_fmt yuv420p -c:a aac (Join-Path $M 'result_video.mp4')
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'ok'
$snapBefore = if (Test-Path -LiteralPath $realGen) { Get-ChildItem -LiteralPath $realGen -Recurse -File | Measure-Object Length -Sum } else { $null }
$env:V3_TEST_GEN = $T; $env:V3_MOCK = $M; $env:KIE_EXEC_INPUTS = $I
$env:HTTP_PROXY = 'http://127.0.0.1:9'; $env:HTTPS_PROXY = 'http://127.0.0.1:9'; $env:ALL_PROXY = 'http://127.0.0.1:9'
$pass = 0; $failn = 0
function Step([string]$title, [string]$script, [string[]]$a, [bool]$expectOk, [string]$expectText = '') {
  $cmd = ". '" + (Join-Path $here 'mocks.ps1') + "'; & '" + (Join-Path $prod $script) + "' " + (($a | ForEach-Object { if ($_ -match '^-[A-Za-z]+$') { $_ } else { "'" + ($_ -replace "'", "''") + "'" } }) -join ' ')
  $out = (pwsh -NoProfile -Command $cmd 2>&1 | Out-String).Trim()
  $ok = ($LASTEXITCODE -eq 0)
  $good = ($ok -eq $expectOk) -and (-not $expectText -or $out -match $expectText)
  if ($good) { $script:pass++; $m = 'PASS' } else { $script:failn++; $m = 'FAIL' }
  $short = ($out -split "`n" | Select-Object -Last 2) -join ' / '
  '{0} {1} — exit {2}: {3}' -f $m, $title, $LASTEXITCODE, ($short.Substring(0, [Math]::Min(260, $short.Length)))
}
Step 'activate' 'v3_activate.ps1' @() $true 'Стартовый баланс: 1037.99'
Step 'activate again refused' 'v3_activate.ps1' @() $false 'уже существует'
Step 'K1 before K0 accepted refused' 'v3_create.ps1' @('-Label', 'K1') $false 'не принят'
Step 'create K0' 'v3_create.ps1' @('-Label', 'K0') $true 'Задача создана: K0 taskId mocktask0001'
Step 'create K0 again refused' 'v3_create.ps1' @('-Label', 'K0') $false 'уже'
Step 'poll K0' 'v3_poll.ps1' @('-Label', 'K0') $true 'creditsConsumed = 12'
Step 'save K0' 'v3_save.ps1' @('-Label', 'K0') $true '"format":"png"'
Step 'save K0 again refused' 'v3_save.ps1' @('-Label', 'K0') $false 'уже сохранён'
Step 'K0-retry1 without reject refused' 'v3_create.ps1' @('-Label', 'K0-retry1') $false 'только после записанного отказа'
Step 'accept K0' 'v3_decide.ps1' @('-Label', 'K0', '-Decision', 'accept', '-Reason', 'dry') $true 'accept K0'
Step 'create K1' 'v3_create.ps1' @('-Label', 'K1') $true 'taskId mocktask0002'
Step 'poll K1' 'v3_poll.ps1' @('-Label', 'K1') $true 'creditsConsumed = 12'
Step 'save K1' 'v3_save.ps1' @('-Label', 'K1') $true 'png'
Step 'reject K1' 'v3_decide.ps1' @('-Label', 'K1', '-Decision', 'reject', '-Reason', 'dry defect') $true 'reject K1'
Step 'A before K1 accepted refused' 'v3_create.ps1' @('-Label', 'A') $false 'не принят'
Step 'addendum on base attempt refused' 'v3_create.ps1' @('-Label', 'A', '-AddendumFile', $addK1) $false 'только для адресного повтора'
Step 'create K1-retry1' 'v3_create.ps1' @('-Label', 'K1-retry1', '-AddendumFile', $addK1) $true 'taskId mocktask0003'
Step 'poll K1-retry1' 'v3_poll.ps1' @('-Label', 'K1-retry1') $true 'creditsConsumed = 12'
Step 'save K1-retry1' 'v3_save.ps1' @('-Label', 'K1-retry1') $true 'png'
Step 'accept K1-retry1' 'v3_decide.ps1' @('-Label', 'K1-retry1', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'create A' 'v3_create.ps1' @('-Label', 'A') $true 'taskId mocktask0004'
Step 'poll A' 'v3_poll.ps1' @('-Label', 'A') $true 'creditsConsumed = 164'
Step 'save A' 'v3_save.ps1' @('-Label', 'A') $true '"audio":true'
Step 'K2 before alast refused' 'v3_create.ps1' @('-Label', 'K2') $false 'не принят|Нет извлечённого'
Step 'accept A' 'v3_decide.ps1' @('-Label', 'A', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Step 'alast' 'v3_alast.ps1' @() $true '720,1280'
Step 'create K2' 'v3_create.ps1' @('-Label', 'K2') $true 'taskId mocktask0005'
Step 'poll K2' 'v3_poll.ps1' @('-Label', 'K2') $true '12'
Step 'save K2' 'v3_save.ps1' @('-Label', 'K2') $true 'png'
Step 'accept K2' 'v3_decide.ps1' @('-Label', 'K2', '-Decision', 'accept', '-Reason', 'dry') $true 'accept'
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'timeout'
Step 'create B with createTask timeout -> unknown, stop' 'v3_create.ps1' @('-Label', 'B') $false 'НЕ повторять'
Set-Content -LiteralPath (Join-Path $M 'scenario.txt') -Value 'ok'
Step 'B again refused (record exists)' 'v3_create.ps1' @('-Label', 'B') $false 'уже'
Step 'any new create refused while unknown open' 'v3_create.ps1' @('-Label', 'K2-retry1') $false 'только после записанного отказа|невыясненная'
# проверки содержимого
$calls = @(Get-Content -LiteralPath (Join-Path $M 'calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
$ct = @($calls | Where-Object call -eq 'createTask')
$chk = @(
  @('createTask отправлен 6 раз (K0, K1, K1-retry1, A, K2, B-timeout)', ($ct.Count -eq 6)),
  @('все createTask с ключом из Set-Key', (@($ct | Where-Object { -not $_.authOk }).Count -eq 0)),
  @('K0: nano-banana-2, 1 референс, 2K 9:16 png', ($ct[0].body.model -eq 'nano-banana-2' -and @($ct[0].body.input.image_input).Count -eq 1 -and $ct[0].body.input.resolution -eq '2K' -and $ct[0].body.input.aspect_ratio -eq '9:16' -and $ct[0].body.input.output_format -eq 'png')),
  @('K1: 2 референса (K0, hero)', (@($ct[1].body.input.image_input).Count -eq 2 -and $ct[1].body.input.image_input[0] -match 'CartoonReels_EP001_V3_K0_' -and $ct[1].body.input.image_input[1] -match 'hero-3d-keyframe')),
  @('K1-retry1 = промпт K1 + перевод строки + правка, 2 референса', (($ct[2].body.input.prompt -ceq ($ct[1].body.input.prompt + "`n" + [IO.File]::ReadAllText($addK1).TrimEnd("`r", "`n"))) -and @($ct[2].body.input.image_input).Count -eq 2)),
  @('A после K1-retry1 — промпт плана без правки', ($ct[3].body.input.prompt -notmatch 'Targeted correction')),
  @('A: seedance-2, first K0, last K1-retry1, 4 c целым, 720p, 9:16, звук true, без reference_*', ($ct[3].body.model -eq 'bytedance/seedance-2' -and $ct[3].body.input.first_frame_url -match 'V3_K0_' -and $ct[3].body.input.last_frame_url -match 'V3_K1-retry1_' -and $ct[3].body.input.duration -is [long] -and $ct[3].body.input.duration -eq 4 -and $ct[3].body.input.resolution -eq '720p' -and $ct[3].body.input.generate_audio -eq $true -and -not (@($ct[3].body.input.Keys) -match '^reference_'))),
  @('K2: 3 референса (A-last, K0, hero)', (@($ct[4].body.input.image_input).Count -eq 3 -and $ct[4].body.input.image_input[0] -match 'A-lastframe' -and $ct[4].body.input.image_input[1] -match 'V3_K0_' -and $ct[4].body.input.image_input[2] -match 'hero')),
  @('B: first A-last, last K2', ($ct[5].body.input.first_frame_url -match 'A-lastframe' -and $ct[5].body.input.last_frame_url -match 'V3_K2_')),
  @('ключ нигде в тестовых файлах', (-not (Get-ChildItem -LiteralPath $T -Recurse -File | Select-String -SimpleMatch 'FAKE-KEY' -List))),
  @('E:\Generations не изменился', ($null -eq $snapBefore -or (Get-ChildItem -LiteralPath $realGen -Recurse -File | Measure-Object Length -Sum).Count -eq $snapBefore.Count))
)
foreach ($c in $chk) { if ($c[1]) { $pass++; 'PASS ' + $c[0] } else { $failn++; 'FAIL ' + $c[0] } }
$env:V3_TEST_GEN = $null; $env:V3_MOCK = $null; $env:KIE_EXEC_INPUTS = $null
. (Join-Path $prod 'v3_lib.ps1') 2>$null
'--- журнал теста (типы): ' + ((Get-Content -LiteralPath (Get-ChildItem -LiteralPath $T -Filter '*journal*').FullName | ForEach-Object { ($_ | ConvertFrom-Json).type }) -join ', ')
'ИТОГО: ' + $pass + ' PASS, ' + $failn + ' FAIL; папка ' + $root
