# ep002_alast.ps1 — последний кадр (индекс 95) выбранного 96-кадрового отрезка принятого A, с той же нормализацией,
# что в первой строке assemble-with-audio.ffmpeg.txt EP002 ($AChain). Без расходов.
. (Join-Path $PSScriptRoot 'ep002_lib.ps1')
$acc = @(Read-Journal | Where-Object { $_.type -in 'accept', 'reject' -and $_.stage -eq 'A' }) | Select-Object -Last 1
if (-not $acc -or $acc.type -ne 'accept') { throw 'A не принят — последний кадр не извлекаю.' }
if ((Get-Sha $acc.file) -ne $acc.sha256) { throw ('Принятый A изменился: ' + $acc.file) }
if (@(Read-Journal | Where-Object { $_.type -eq 'alast' -and $_.sourceSha256 -eq $acc.sha256 }).Count) { throw 'Последний кадр этого A уже извлечён.' }
$fltLine = @([IO.File]::ReadAllLines((Join-Path $Dl 'assemble-with-audio.ffmpeg.txt')))[0]
if ($fltLine -cne ('[0:v]' + $AChain + '[v0];')) { throw ('Нормализация A не совпадает с фильтром сборки: ' + $fltLine) }
$lines = @(ffmpeg -v error -i $acc.file -vf $AChain -an -f framemd5 - 2>$null)
$fr = @($lines | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($fr.Count -ne 96) { throw ('Отрезок A после нормализации даёт ' + $fr.Count + ' кадров, ожидалось 96. Пустыми стоп-кадрами не добиваю.') }
$out = Join-Path $Gen ($Pfx + '_A-lastframe_' + (New-Stamp) + '.png')
ffmpeg -v error -i $acc.file -vf ($AChain + ',select=eq(n\,95)') -frames:v 1 -fps_mode passthrough $out
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) { throw 'Не удалось извлечь кадр 95.' }
$dims = (ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $out)
# сверка выбора: кадр, который отдаёт select=eq(n,95), побитно равен 96-му кадру нормализованного отрезка (md5 до перевода в PNG)
$md5Src = ((@($fr)[95] -split ',')[-1]).Trim()
$md5Sel = (@(ffmpeg -v error -i $acc.file -vf ($AChain + ',select=eq(n\,95)') -frames:v 1 -fps_mode passthrough -an -f framemd5 - 2>$null | Where-Object { $_ -and -not $_.StartsWith('#') })[0] -split ',')[-1].Trim()
if ($md5Src -ne $md5Sel) { [IO.File]::Delete($out); throw ('Выбранный кадр не совпал с кадром 95 отрезка (md5 ' + $md5Sel + ' / ' + $md5Src + ').') }
$k1 = @(Read-Journal | Where-Object { $_.type -in 'accept', 'reject' -and $_.stage -eq 'K1' }) | Select-Object -Last 1
$ssim = $null
if ($k1 -and $k1.type -eq 'accept') {
  $sl = (ffmpeg -hide_banner -nostats -i $out -i $k1.file -lavfi '[1:v]scale=720:1280:flags=lanczos,format=yuv420p[b];[0:v]format=yuv420p[a];[a][b]ssim' -f null - 2>&1 | Out-String)
  if ($sl -match 'All:([\d.]+)') { $ssim = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) }
}
$sha = Get-Sha $out
[IO.File]::WriteAllLines(($out -replace '\.png$', '.log.txt'), [string[]]@(
    ([IO.Path]::GetFileName($out) + ' | последний кадр (индекс 95) отрезка 96 кадров / 4 с принятого A | ' + $dims + ' | sha256=' + $sha + ' | сохранено ' + (New-Stamp)),
    ('источник: ' + $acc.file + ' sha256=' + $acc.sha256 + ' | нормализация: ' + $AChain + ' | кадров в отрезке: ' + $fr.Count + ' | md5 кадра 95 отрезка = md5 выбранного кадра: ' + $md5Src),
    ('SSIM с принятым K1 (масштаб 720×1280, только для сведения): ' + $ssim)
  ), $Utf8)
Add-Journal ([ordered]@{ type = 'alast'; file = $out; sha256 = $sha; dims = $dims; sourceFile = $acc.file; sourceSha256 = $acc.sha256; frameIndex = 95; segment = '96 frames @24 fps'; chain = $AChain; frame95Md5 = $md5Src; ssimVsK1 = $ssim })
'Последний кадр A: ' + $out + ' (' + $dims + '), кадр 95 сверен по md5, SSIM с K1 = ' + $ssim
