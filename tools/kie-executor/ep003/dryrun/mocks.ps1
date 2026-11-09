# Моки сети для сухого прогона ep003. Реальная сеть дополнительно перекрыта прокси 127.0.0.1:9.
# Цены: nano-banana-2 2K = 12 (или значение из nbprice.txt), seedance-2 720p = 41 × duration; результат видео — ролик нужной длины со звуком.
# scenario.txt: ok | timeout | reject422 | code500 (createTask) | pollslow (recordInfo отвечает generating и не списывает).
$M = $env:EP003_MOCK
function global:MockState { if (Test-Path "$M\state.json") { Get-Content -Raw "$M\state.json" | ConvertFrom-Json -AsHashtable } else { @{ balance = 1220.99; n = 0; tasks = @{}; charged = @{} } } }
function global:SaveState($s) { $s | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$M\state.json" -Encoding utf8 }
function global:LogCall($o) { Add-Content -LiteralPath "$M\calls.jsonl" -Value ($o | ConvertTo-Json -Compress -Depth 8) -Encoding utf8 }
function global:curl.exe {
  $file = $null; $name = $null; $upPath = $null
  foreach ($a in $args) { if ($a -match '^file=@(.+);type=') { $file = $Matches[1] } elseif ($a -match '^fileName=(.+)$') { $name = $Matches[1] } elseif ($a -match '^uploadPath=(.+)$') { $upPath = $Matches[1] } }
  if (-not (Test-Path -LiteralPath $file)) { $global:LASTEXITCODE = 26; return }
  New-Item -ItemType Directory -Force -Path "$M\up" | Out-Null
  Copy-Item -LiteralPath $file -Destination "$M\up\$name"
  LogCall @{ call = 'upload'; file = $file; name = $name; uploadPath = $upPath; authHeader = ($args -join ' ' -match 'Bearer FAKE-KEY') }
  $global:LASTEXITCODE = 0
  (@{ success = $true; code = 200; msg = 'ok'; data = @{ downloadUrl = "https://mock.test/up/$name"; fileSize = (Get-Item -LiteralPath $file).Length; mimeType = 'image/png' } } | ConvertTo-Json -Compress)
}
function global:Invoke-WebRequest {
  param($Uri, $OutFile, $TimeoutSec, [switch]$PassThru, $UserAgent)
  if ($Uri -like 'https://mock.test/up/*') { Copy-Item -LiteralPath ("$M\up\" + ($Uri -replace '^.*/', '')) -Destination $OutFile; return }
  if ($Uri -eq 'https://mock.test/result/image') { Copy-Item -LiteralPath "$M\result_image.png" -Destination $OutFile; return }
  if ($Uri -match '^https://mock\.test/result/video(\d+)$') { Copy-Item -LiteralPath ("$M\result_video" + $Matches[1] + '.mp4') -Destination $OutFile; return }
  throw "MOCK: сеть закрыта ($Uri)"
}
function global:Invoke-RestMethod {
  param($Uri, $Method, $Headers, $ContentType, $Body, $TimeoutSec, [switch]$SkipHttpErrorCheck, $StatusCodeVariable, $UserAgent)
  if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
  $s = MockState
  if ($Uri -like '*model-pricing/page*') {
    $nbp = if (Test-Path "$M\nbprice.txt") { [double](Get-Content -Raw "$M\nbprice.txt").Trim() } else { 12 }
    LogCall @{ call = 'pricing'; body = [string]$Body; auth = [bool]$Headers }
    $rows = if ([string]$Body -match 'nano banana 2') { @([pscustomobject]@{ modelDescription = 'Google nano banana 2, 4K'; creditPrice = 18; creditUnit = 'per image'; usdPrice = '0.09' }, [pscustomobject]@{ modelDescription = 'Google nano banana 2, 2K'; creditPrice = $nbp; creditUnit = 'per image'; usdPrice = '0.06' }) }
            else { @([pscustomobject]@{ modelDescription = 'bytedance/seedance-2, 720p with video input'; creditPrice = 25; creditUnit = 'per second'; usdPrice = '0.125' }, [pscustomobject]@{ modelDescription = 'bytedance/seedance-2, 720p no video input'; creditPrice = 41; creditUnit = 'per second'; usdPrice = '0.205' }) }
    return [pscustomobject]@{ code = 200; msg = 'success'; data = [pscustomobject]@{ total = $rows.Count; records = $rows } }
  }
  if ($Uri -like '*chat/credit*') { return [pscustomobject]@{ code = 200; msg = 'success'; data = $s.balance } }
  if ($Uri -like '*jobs/createTask*') {
    $json = [Text.Encoding]::UTF8.GetString($Body); $b = $json | ConvertFrom-Json -AsHashtable
    LogCall @{ call = 'createTask'; body = $b; authOk = ($Headers.Authorization -eq 'Bearer FAKE-KEY-dryrun-0000') }
    $sc = (Get-Content -Raw "$M\scenario.txt").Trim()
    if ($sc -eq 'timeout') { throw [System.Net.Http.HttpRequestException]::new('MOCK timeout') }
    if ($sc -eq 'reject422') { return [pscustomobject]@{ code = 422; msg = 'MOCK bad param'; data = $null } }
    if ($sc -eq 'code500') { return [pscustomobject]@{ code = 500; msg = 'MOCK server error'; data = $null } }
    $s.n = $s.n + 1; $id = 'mocktask' + $s.n.ToString('0000')
    if ($b.model -eq 'nano-banana-2') { $s.tasks[$id] = @{ kind = 'image'; price = 12 } }
    else { $s.tasks[$id] = @{ kind = 'video' + [int]$b.input.duration; price = 41 * [int]$b.input.duration } }
    SaveState $s
    return [pscustomobject]@{ code = 200; msg = 'success'; data = [pscustomobject]@{ taskId = $id } }
  }
  if ($Uri -like '*jobs/recordInfo*') {
    $id = $Uri -replace '^.*taskId=', ''; $t = $s.tasks[$id]
    LogCall @{ call = 'recordInfo'; taskId = $id }
    if (-not $t) { return [pscustomobject]@{ code = 422; msg = 'recordInfo is null'; data = $null } }
    if ((Get-Content -Raw "$M\scenario.txt").Trim() -eq 'pollslow') { return [pscustomobject]@{ code = 200; msg = 'success'; data = [pscustomobject]@{ taskId = $id; state = 'generating' } } }
    if (-not $s.charged[$id]) { $s.balance = [Math]::Round($s.balance - $t.price, 2); $s.charged[$id] = $true; SaveState $s }
    $rj = '{"resultUrls":["https://mock.test/result/' + $t.kind + '"]}'
    return [pscustomobject]@{ code = 200; msg = 'success'; data = [pscustomobject]@{ taskId = $id; state = 'success'; resultJson = $rj; creditsConsumed = $t.price; costTime = 7 } }
  }
  throw "MOCK: неожиданный URL $Uri"
}
function global:Start-Sleep { param($Seconds, $Milliseconds) }
