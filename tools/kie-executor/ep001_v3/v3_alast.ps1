# v3_alast.ps1 — последний кадр выбранного 4-секундного отрезка принятого A (та же нормализация, что в фильтре монтажа). Без расходов.
. (Join-Path $PSScriptRoot 'v3_lib.ps1')
$acc = @(Read-Journal | Where-Object { $_.type -in 'accept', 'reject' -and $_.stage -eq 'A' }) | Select-Object -Last 1
if (-not $acc -or $acc.type -ne 'accept') { throw 'A не принят — последний кадр не извлекаю.' }
if ((Get-Sha $acc.file) -ne $acc.sha256) { throw ('Принятый A изменился: ' + $acc.file) }
if (@(Read-Journal | Where-Object { $_.type -eq 'alast' -and $_.sourceSha256 -eq $acc.sha256 }).Count) { throw 'Последний кадр этого A уже извлечён.' }
$chain = 'trim=start=0:end=4,setpts=PTS-STARTPTS,fps=24,scale=720:1280,setsar=1'
$lines = @(ffmpeg -v error -i $acc.file -vf $chain -an -f framemd5 - 2>$null)
$n = @($lines | Where-Object { $_ -and -not $_.StartsWith('#') }).Count
if ($n -ne 96) { throw ('Отрезок A [0;4) после нормализации даёт ' + $n + ' кадров, ожидалось 96.') }
$out = Join-Path $Gen ($Pfx + '_A-lastframe_' + (New-Stamp) + '.png')
ffmpeg -v error -i $acc.file -vf ($chain + ',select=eq(n\,95)') -frames:v 1 -fps_mode passthrough $out
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) { throw 'Не удалось извлечь кадр 95.' }
$dims = (ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $out)
$k1 = @(Read-Journal | Where-Object { $_.type -eq 'accept' -and $_.stage -eq 'K1' }) | Select-Object -Last 1
$ssim = $null
if ($k1) {
  $sl = (ffmpeg -hide_banner -nostats -i $out -i $k1.file -lavfi '[1:v]scale=720:1280:flags=lanczos,format=yuv420p[b];[0:v]format=yuv420p[a];[a][b]ssim' -f null - 2>&1 | Out-String)
  if ($sl -match 'All:([\d.]+)') { $ssim = [double]$Matches[1] }
}
$sha = Get-Sha $out
[IO.File]::WriteAllLines(($out -replace '\.png$', '.log.txt'), [string[]]@(
    ([IO.Path]::GetFileName($out) + ' | последний кадр (индекс 95) отрезка 0–4 с принятого A | ' + $dims + ' | sha256=' + $sha + ' | сохранено ' + (New-Stamp)),
    ('источник: ' + $acc.file + ' sha256=' + $acc.sha256 + ' | нормализация: ' + $chain + ' | кадров в отрезке: ' + $n),
    ('SSIM с принятым K1 (масштаб 720×1280, только для сведения): ' + $ssim)
  ), $Utf8)
Add-Journal ([ordered]@{ type = 'alast'; file = $out; sha256 = $sha; dims = $dims; sourceFile = $acc.file; sourceSha256 = $acc.sha256; frameIndex = 95; segment = '0-4 s'; chain = $chain; ssimVsK1 = $ssim })
'Последний кадр A: ' + $out + ' (' + $dims + '), SSIM с K1 = ' + $ssim
