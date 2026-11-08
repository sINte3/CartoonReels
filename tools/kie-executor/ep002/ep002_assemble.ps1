# ep002_assemble.ps1 — БЕСПЛАТНО, только локально: монтаж EP002 из принятых A (96 кадров) и B (120 кадров) со звуком.
# Фильтр — assemble-with-audio.ffmpeg.txt коммита пакета: без укрупнения B, выходы [v] и [aout]; без -an.
# Результаты: 720p-мастер 9 с / 216 кадров, обычное масштабирование 1080p (lanczos, звук копией), дополнительная маленькая тихая копия.
# -MeasureOnly: только проверить исходники и вывести громкость (ebur128/volumedetect) для выбора -GainA/-GainB; файлы не пишутся.
param([double]$GainA = 0, [double]$GainB = 0, [switch]$NoSilent, [switch]$MeasureOnly)
. (Join-Path $PSScriptRoot 'ep002_lib.ps1')
$Inv = [Globalization.CultureInfo]::InvariantCulture
$FilterSrc = Join-Path $Dl 'assemble-with-audio.ffmpeg.txt'
$Frames = 216; $Seconds = 9.0
$Need = @{ A = @{ frames = 96; seconds = 4.0 }; B = @{ frames = 120; seconds = 5.0 } }

function Get-AcceptedVideo([string]$st) {
  $a = @(Read-Journal | Where-Object { $_.type -in 'accept', 'reject' -and $_.stage -eq $st }) | Select-Object -Last 1
  if (-not $a -or $a.type -ne 'accept') { throw ('Этап ' + $st + ' не принят — монтаж не запускаю.') }
  if ($a.file -notmatch '\.mp4$') { throw ('Принятый ' + $st + ' не видео: ' + $a.file) }
  if ((Get-Sha $a.file) -ne $a.sha256) { throw ('Файл принятого ' + $st + ' изменился: ' + $a.file) }
  $a
}
function Probe([string]$f) {
  $j = ffprobe -v error -count_frames -show_entries 'stream=index,codec_type,codec_name,profile,pix_fmt,width,height,sample_aspect_ratio,r_frame_rate,nb_read_frames,sample_rate,channels,channel_layout,duration' -show_entries 'format=duration,format_name,bit_rate' -of json $f
  if ($LASTEXITCODE -ne 0) { throw ('ffprobe не прочитал ' + $f) }
  ($j | Out-String) | ConvertFrom-Json -AsHashtable
}
function Get-Vol([string]$f) {
  $o = ffmpeg -hide_banner -nostats -i $f -vn -af volumedetect -f null - 2>&1 | Out-String
  $mn = [regex]::Match($o, 'mean_volume: (-?[\d\.]+) dB'); $mx = [regex]::Match($o, 'max_volume: (-?[\d\.]+) dB')
  if (-not $mn.Success -or -not $mx.Success) { throw ('volumedetect не дал уровней для ' + $f) }
  [ordered]@{ mean_db = [double]::Parse($mn.Groups[1].Value, $Inv); max_db = [double]::Parse($mx.Groups[1].Value, $Inv) }
}
function Get-Loud([string]$f, [string]$trim = '') {
  $af = $(if ($trim) { $trim + ',' } else { '' }) + 'ebur128=peak=true'
  $o = ffmpeg -hide_banner -nostats -i $f -vn -af $af -f null - 2>&1 | Out-String
  $sum = $o.Substring([Math]::Max(0, $o.LastIndexOf('Summary:')))
  $i = [regex]::Match($sum, 'I:\s+(-?[\d\.]+) LUFS'); $p = [regex]::Match($sum, 'Peak:\s+(-?[\d\.]+) dBFS')
  [ordered]@{ integrated_lufs = $(if ($i.Success) { [double]::Parse($i.Groups[1].Value, $Inv) }); true_peak_dbfs = $(if ($p.Success) { [double]::Parse($p.Groups[1].Value, $Inv) }) }
}
function Get-TopAtoms([string]$f) {
  $fs = [IO.File]::OpenRead($f); $atoms = [Collections.Generic.List[string]]::new()
  try {
    $pos = 0L; $b = New-Object byte[] 16
    while ($pos + 8 -le $fs.Length) {
      $fs.Position = $pos; [void]$fs.Read($b, 0, 8)
      $size = [long]((([uint32]$b[0]) -shl 24) -bor (([uint32]$b[1]) -shl 16) -bor (([uint32]$b[2]) -shl 8) -bor ([uint32]$b[3]))
      $type = [Text.Encoding]::ASCII.GetString($b, 4, 4)
      if ($size -eq 1) { [void]$fs.Read($b, 8, 8); $size = 0L; for ($k = 8; $k -lt 16; $k++) { $size = ($size -shl 8) -bor $b[$k] } }
      elseif ($size -eq 0) { $size = $fs.Length - $pos }
      $atoms.Add($type)
      if ($size -lt 8) { break }
      $pos += $size
    }
  } finally { $fs.Dispose() }
  , $atoms.ToArray()
}
function Test-Decode([string]$f) {
  $o = ffmpeg -hide_banner -nostats -v error -i $f -f null - 2>&1 | Out-String
  [ordered]@{ exit = $LASTEXITCODE; stderr = $o.Trim() }
}
function Get-Stream($p, [string]$t) { , @($p.streams | Where-Object { $_.codec_type -eq $t }) }   # запятая: один поток не разворачивать в hashtable

# ---------- источники ----------
if ((Get-Sha $FilterSrc) -ne $FilterSha) { throw 'Фильтр сборки не совпал с зафиксированным SHA-256.' }
$A = Get-AcceptedVideo 'A'; $B = Get-AcceptedVideo 'B'
$src = [ordered]@{}
foreach ($pair in @(@('A', $A), @('B', $B))) {
  $n = $pair[0]; $e = $pair[1]; $p = Probe $e.file; $nd = $Need[$n]
  $v = Get-Stream $p 'video'; $au = Get-Stream $p 'audio'
  if ($v.Count -ne 1) { throw ($n + ': видеопотоков ' + $v.Count) }
  if ([int]$v[0].width -ne 720 -or [int]$v[0].height -ne 1280) { throw ($n + ': ожидался вертикальный 720×1280, получено ' + $v[0].width + '×' + $v[0].height) }
  if ($v[0].r_frame_rate -ne '24/1') { throw ($n + ': ожидалось 24 fps, получено ' + $v[0].r_frame_rate) }
  if ([int]$v[0].nb_read_frames -lt $nd.frames -or [double]::Parse($v[0].duration, $Inv) -lt $nd.seconds) { throw ($n + ': меньше ' + $nd.seconds + ' с / ' + $nd.frames + ' кадров — монтаж 9 с невозможен без досъёмки, пустыми кадрами не добиваю') }
  if ($au.Count -lt 1 -or [int]$au[0].nb_read_frames -lt 1) { throw ($n + ': нет непустой аудиодорожки') }
  if ([double]::Parse($au[0].duration, $Inv) -lt $nd.seconds - 0.05) { throw ($n + ': аудио короче ' + $nd.seconds + ' с (' + $au[0].duration + ') — padding не подменяет отсутствующий звук') }
  $vol = Get-Vol $e.file
  if ($vol.max_db -lt -60) { throw ($n + ': аудиодорожка фактически тихая (max ' + $vol.max_db + ' dB)') }
  $dec = Test-Decode $e.file
  if ($dec.exit -ne 0 -or $dec.stderr) { throw ($n + ': ошибки полного декодирования: ' + $dec.stderr) }
  $seg = 'atrim=start=0:end=' + $nd.seconds.ToString('0.###', $Inv)
  $src[$n] = [ordered]@{ file = $e.file; sha256 = $e.sha256; taskId = $e.taskId; video = $v[0]; audio = $au[0]; volume = $vol; loudness = (Get-Loud $e.file); loudness_used_segment = (Get-Loud $e.file $seg) }
}
if ($MeasureOnly) {
  [ordered]@{ A = [ordered]@{ frames = $src.A.video.nb_read_frames; duration = $src.A.video.duration; audio_s = $src.A.audio.duration; vol = $src.A.volume; loud = $src.A.loudness; loud_0_4s = $src.A.loudness_used_segment }
    B = [ordered]@{ frames = $src.B.video.nb_read_frames; duration = $src.B.video.duration; audio_s = $src.B.audio.duration; vol = $src.B.volume; loud = $src.B.loudness; loud_0_5s = $src.B.loudness_used_segment } } | ConvertTo-Json -Depth 6
  return
}

# ---------- фильтр ----------
$fltText = [IO.File]::ReadAllText($FilterSrc)
$fltSha = Get-Sha $FilterSrc
$stamp = New-Stamp
$fltUsed = $FilterSrc
if ($GainA -ne 0 -or $GainB -ne 0) {
  $lines = $fltText -split "`n"
  $fix = { param($line, $g) $line -replace 'channel_layouts=stereo,apad', ('channel_layouts=stereo,volume=' + $g.ToString('0.0#', $Inv) + 'dB,apad') }
  $hit = @{ A = $false; B = $false }
  for ($k = 0; $k -lt $lines.Count; $k++) {
    if ($lines[$k] -like '`[0:a`]*' -and $GainA -ne 0) { $lines[$k] = & $fix $lines[$k] $GainA; $hit.A = $lines[$k] -match 'volume=' }
    if ($lines[$k] -like '`[1:a`]*' -and $GainB -ne 0) { $lines[$k] = & $fix $lines[$k] $GainB; $hit.B = $lines[$k] -match 'volume=' }
  }
  if (($GainA -ne 0 -and -not $hit.A) -or ($GainB -ne 0 -and -not $hit.B)) { throw 'Не удалось вставить усиление в фильтр.' }
  $fltUsed = Join-Path $Gen ($Pfx + '_assemble-with-audio.gain_' + $stamp + '.ffmpeg.txt')
  [IO.File]::WriteAllText($fltUsed, ($lines -join "`n"), $Utf8)
}
$fltUsedSha = Get-Sha $fltUsed

# ---------- 720p мастер ----------
$name720 = $Pfx + '_9s_sound_720p_' + $stamp + '.mp4'
$out720 = Join-Path $Gen $name720
$args720 = @('-hide_banner', '-nostats', '-v', 'error', '-y', '-i', $A.file, '-i', $B.file, '-/filter_complex', $fltUsed, '-map', '[v]', '-map', '[aout]',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-r', '24', '-fps_mode', 'cfr',
  '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2', '-movflags', '+faststart', '-f', 'mp4', ($out720 + '.part'))
& ffmpeg @args720
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg: сборка 720p не удалась' }

function Test-Output([string]$f, [int]$w, [int]$h, [bool]$audio) {
  $p = Probe $f; $v = Get-Stream $p 'video'; $au = Get-Stream $p 'audio'
  $atoms = Get-TopAtoms $f
  $dec = Test-Decode $f
  $r = [ordered]@{
    container = $p.format.format_name; duration_s = $p.format.duration; bit_rate = $p.format.bit_rate
    video = $v[0]; audio = $(if ($au.Count) { $au[0] }); top_atoms = ($atoms -join ','); full_decode_exit = $dec.exit; full_decode_stderr = $dec.stderr
  }
  $checks = [ordered]@{
    one_video_h264 = ($v.Count -eq 1 -and $v[0].codec_name -eq 'h264' -and $v[0].pix_fmt -eq 'yuv420p')
    size = ([int]$v[0].width -eq $w -and [int]$v[0].height -eq $h)
    fps_24 = ($v[0].r_frame_rate -eq '24/1')
    frames_216 = ([int]$v[0].nb_read_frames -eq $Frames)
    duration_9s = ([Math]::Abs([double]::Parse($p.format.duration, $Inv) - $Seconds) -lt 0.03)
    faststart_moov_before_mdat = ([Array]::IndexOf($atoms, 'moov') -ge 0 -and [Array]::IndexOf($atoms, 'moov') -lt [Array]::IndexOf($atoms, 'mdat'))
    full_decode_clean = ($dec.exit -eq 0 -and -not $dec.stderr)
  }
  if ($audio) {
    $vol = Get-Vol $f; $r['volume'] = $vol; $r['loudness'] = Get-Loud $f
    $checks['audio_aac_48k_stereo'] = ($au.Count -eq 1 -and $au[0].codec_name -eq 'aac' -and $au[0].sample_rate -eq '48000' -and [int]$au[0].channels -eq 2)
    $checks['audio_duration_9s'] = ($au.Count -eq 1 -and [Math]::Abs([double]::Parse($au[0].duration, $Inv) - $Seconds) -lt 0.05)
    $checks['audio_not_silent'] = ($vol.max_db -gt -40)
    $checks['no_clipping'] = ($vol.max_db -le -0.5)
  } else { $checks['no_audio_stream'] = ($au.Count -eq 0) }
  $r['checks'] = $checks
  $r['all_ok'] = -not ($checks.Values -contains $false)
  $r
}
$chk720 = Test-Output ($out720 + '.part') 720 1280 $true
if (-not $chk720.all_ok) { throw ('Проверка 720p не прошла: ' + ($chk720.checks | ConvertTo-Json -Compress) + ' / файл оставлен как .part') }
Move-Item -LiteralPath ($out720 + '.part') -Destination $out720
$sha720 = Get-Sha $out720

# ---------- 1080p: обычное масштабирование того же монтажа ----------
$name1080 = $Pfx + '_9s_sound_1080p_' + $stamp + '.mp4'
$out1080 = Join-Path $Gen $name1080
$args1080 = @('-hide_banner', '-nostats', '-v', 'error', '-y', '-i', $out720, '-map', '0:v:0', '-map', '0:a:0', '-vf', 'scale=1080:1920:flags=lanczos,setsar=1',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-r', '24', '-fps_mode', 'cfr', '-c:a', 'copy', '-movflags', '+faststart', '-f', 'mp4', ($out1080 + '.part'))
& ffmpeg @args1080
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg: экспорт 1080p не удался' }
$chk1080 = Test-Output ($out1080 + '.part') 1080 1920 $true
if (-not $chk1080.all_ok) { throw ('Проверка 1080p не прошла: ' + ($chk1080.checks | ConvertTo-Json -Compress)) }
Move-Item -LiteralPath ($out1080 + '.part') -Destination $out1080
$sha1080 = Get-Sha $out1080

# ---------- дополнительная маленькая тихая копия ----------
$outS = $null; $chkS = $null; $shaS = $null; $argsS = $null
if (-not $NoSilent) {
  $outS = Join-Path $Gen ($Pfx + '_9s_silent_720p-small_' + $stamp + '.mp4')
  $argsS = @('-hide_banner', '-nostats', '-v', 'error', '-y', '-i', $out720, '-map', '0:v:0', '-an', '-c:v', 'libx264', '-preset', 'slow', '-crf', '26', '-pix_fmt', 'yuv420p', '-r', '24', '-fps_mode', 'cfr', '-movflags', '+faststart', '-f', 'mp4', ($outS + '.part'))
  & ffmpeg @argsS
  if ($LASTEXITCODE -ne 0) { throw 'ffmpeg: тихая копия не удалась' }
  $chkS = Test-Output ($outS + '.part') 720 1280 $false
  if (-not $chkS.all_ok) { throw ('Проверка тихой копии не прошла: ' + ($chkS.checks | ConvertTo-Json -Compress)) }
  Move-Item -LiteralPath ($outS + '.part') -Destination $outS
  $shaS = Get-Sha $outS
}

# ---------- логи рядом с файлами и журнал ----------
function Write-OutLog([string]$file, [string]$what, $chk, [string[]]$ffArgs, [string]$sha) {
  $log = [ordered]@{
    file = (Split-Path $file -Leaf); sha256 = $sha; bytes = (Get-Item -LiteralPath $file).Length; created = (Now); what = $what
    package = $Episode + ', commit ' + $Commit
    sources = [ordered]@{ A = [ordered]@{ file = (Split-Path $src.A.file -Leaf); sha256 = $src.A.sha256; taskId = $src.A.taskId; loudness = $src.A.loudness_used_segment }; B = [ordered]@{ file = (Split-Path $src.B.file -Leaf); sha256 = $src.B.sha256; taskId = $src.B.taskId; loudness = $src.B.loudness_used_segment } }
    filter = [ordered]@{ source = (Split-Path $FilterSrc -Leaf); source_sha256 = $fltSha; used = (Split-Path $fltUsed -Leaf); used_sha256 = $fltUsedSha; gainA_db = $GainA; gainB_db = $GainB }
    ffmpeg_args = ($ffArgs -join ' ')
    verification = $chk
    note = 'Проверки техническими средствами (ffprobe, полное декодирование, volumedetect/ebur128, порядок атомов). Субъективного прослушивания не было.'
  }
  [IO.File]::WriteAllText(($file -replace '\.mp4$', '.log.txt'), ($log | ConvertTo-Json -Depth 10), $Utf8)
}
Write-OutLog $out720 '720p мастер со звуком: A кадры 0–95 (0–4 с) + B кадры 0–119 (4–9 с), без укрупнения, AAC 48 кГц стерео, лимитер −1 dBFS, faststart' $chk720 $args720 $sha720
Write-OutLog $out1080 '1080p: обычное масштабирование lanczos того же 720p-монтажа, звук скопирован без перекодирования; не новая детализация' $chk1080 $args1080 $sha1080
if ($outS) { Write-OutLog $outS 'дополнительная маленькая тихая копия того же монтажа (без звука); основные файлы со звуком' $chkS $argsS $shaS }
Add-Journal ([ordered]@{ type = 'assembled'; stamp = $stamp; A = $src.A.file; A_sha256 = $src.A.sha256; B = $src.B.file; B_sha256 = $src.B.sha256; filter_sha256 = $fltUsedSha; gainA_db = $GainA; gainB_db = $GainB
    out720 = $out720; out720_sha256 = $sha720; out1080 = $out1080; out1080_sha256 = $sha1080; silent = $outS; silent_sha256 = $shaS; checks720 = $chk720.checks; checks1080 = $chk1080.checks })
[ordered]@{
  sources = [ordered]@{ A = [ordered]@{ loud = $src.A.loudness_used_segment; vol = $src.A.volume; frames = $src.A.video.nb_read_frames }; B = [ordered]@{ loud = $src.B.loudness_used_segment; vol = $src.B.volume; frames = $src.B.video.nb_read_frames } }
  out720 = [ordered]@{ file = $out720; sha256 = $sha720; checks = $chk720.checks; volume = $chk720.volume; loudness = $chk720.loudness; atoms = $chk720.top_atoms }
  out1080 = [ordered]@{ file = $out1080; sha256 = $sha1080; checks = $chk1080.checks; atoms = $chk1080.top_atoms }
  silent = $(if ($outS) { [ordered]@{ file = $outS; sha256 = $shaS; checks = $chkS.checks } })
} | ConvertTo-Json -Depth 8
