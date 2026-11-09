# ep003_clast.ps1 — последний кадр (индекс 119) выбранного 120-кадрового отрезка принятого C, с той же нормализацией,
# что во второй строке assemble-with-audio.ffmpeg.txt EP003 ($CChain). Без расходов. K1 реальный конец C не заменяет.
. (Join-Path $PSScriptRoot 'ep003_lib.ps1')
$acc = @(Read-Journal | Where-Object { $_.type -in 'accept', 'reject' -and $_.stage -eq 'C' }) | Select-Object -Last 1
if (-not $acc -or $acc.type -ne 'accept') { throw 'C не принят — последний кадр не извлекаю.' }
if ((Get-Sha $acc.file) -ne $acc.sha256) { throw ('Принятый C изменился: ' + $acc.file) }
if (@(Read-Journal | Where-Object { $_.type -eq 'clast' -and $_.sourceSha256 -eq $acc.sha256 }).Count) { throw 'Последний кадр этого C уже извлечён.' }
$fltLine = @([IO.File]::ReadAllLines((Join-Path $Dl 'assemble-with-audio.ffmpeg.txt')))[1]
if ($fltLine -cne ('[1:v]' + $CChain + '[v1];')) { throw ('Нормализация C не совпадает с фильтром сборки: ' + $fltLine) }
$lines = @(ffmpeg -v error -i $acc.file -vf $CChain -an -f framemd5 - 2>$null)
$fr = @($lines | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($fr.Count -ne 120) { throw ('Отрезок C после нормализации даёт ' + $fr.Count + ' кадров, ожидалось 120. Пустыми стоп-кадрами не добиваю.') }
$out = Join-Path $Gen ($Pfx + '_C-lastframe_' + (New-Stamp) + '.png')
ffmpeg -v error -i $acc.file -vf ($CChain + ',select=eq(n\,119)') -frames:v 1 -fps_mode passthrough $out
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) { throw 'Не удалось извлечь кадр 119.' }
$dims = (ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $out)
# сверка выбора: кадр, который отдаёт select=eq(n,119), побитно равен 120-му кадру нормализованного отрезка (md5 до перевода в PNG)
$md5Src = ((@($fr)[119] -split ',')[-1]).Trim()
$md5Sel = (@(ffmpeg -v error -i $acc.file -vf ($CChain + ',select=eq(n\,119)') -frames:v 1 -fps_mode passthrough -an -f framemd5 - 2>$null | Where-Object { $_ -and -not $_.StartsWith('#') })[0] -split ',')[-1].Trim()
if ($md5Src -ne $md5Sel) { [IO.File]::Delete($out); throw ('Выбранный кадр не совпал с кадром 119 отрезка (md5 ' + $md5Sel + ' / ' + $md5Src + ').') }
$k1 = @(Read-Journal | Where-Object { $_.type -in 'accept', 'reject' -and $_.stage -eq 'K1' }) | Select-Object -Last 1
$ssim = $null
if ($k1 -and $k1.type -eq 'accept') {
  $sl = (ffmpeg -hide_banner -nostats -i $out -i $k1.file -lavfi '[1:v]scale=720:1280:flags=lanczos,format=yuv420p[b];[0:v]format=yuv420p[a];[a][b]ssim' -f null - 2>&1 | Out-String)
  if ($sl -match 'All:([\d.]+)') { $ssim = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) }
}
$sha = Get-Sha $out
[IO.File]::WriteAllLines(($out -replace '\.png$', '.log.txt'), [string[]]@(
    ([IO.Path]::GetFileName($out) + ' | последний кадр (индекс 119) отрезка 120 кадров / 5 с принятого C | ' + $dims + ' | sha256=' + $sha + ' | сохранено ' + (New-Stamp)),
    ('источник: ' + $acc.file + ' sha256=' + $acc.sha256 + ' | нормализация: ' + $CChain + ' | кадров в отрезке: ' + $fr.Count + ' | md5 кадра 119 отрезка = md5 выбранного кадра: ' + $md5Src),
    ('SSIM с принятым K1 (масштаб 720×1280, только для сведения): ' + $ssim)
  ), $Utf8)
Add-Journal ([ordered]@{ type = 'clast'; file = $out; sha256 = $sha; dims = $dims; sourceFile = $acc.file; sourceSha256 = $acc.sha256; frameIndex = 119; segment = '120 frames @24 fps'; chain = $CChain; frame119Md5 = $md5Src; ssimVsK1 = $ssim })
'Последний кадр C: ' + $out + ' (' + $dims + '), кадр 119 сверен по md5, SSIM с K1 = ' + $ssim
