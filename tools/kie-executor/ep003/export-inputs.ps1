# export-inputs.ps1 — бесплатно и без сети: достаёт из локального git точные файлы зафиксированного коммита пакета EP003
# ($Commit из ep003_lib.ps1) с сохранением байтов: plan.json, фильтр сборки, пять промптов, README.md, карточку CLAUDE_PRODUCE_FULL_RU.md,
# готовое 7-секундное начало (deliverables/ep002/EP002_timing_7s_sound_720p.mp4 → opening-7s.mp4) и его кадр 167
# (episodes/EP003/references/opening-lastframe.png → opening-lastframe.png). Бинарные файлы пишутся байтами, SHA-256 сверяется с plan.json.
# prompts/K0-medal-ready.prompt.en.txt → prompts__K0-medal-ready.prompt.en.txt. Папка по умолчанию inputs/ (в .gitignore).
param([string]$Dest = (Join-Path $PSScriptRoot 'inputs'))
. (Join-Path $PSScriptRoot 'ep003_lib.ps1')
$repo = (git -C $PSScriptRoot rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0 -or -not $repo) { throw 'Скрипт должен лежать внутри git-репозитория CartoonReels.' }
function Get-Blob([string]$path) {
  $psi = [Diagnostics.ProcessStartInfo]::new('git')
  foreach ($a in @('-C', $repo.Trim(), 'cat-file', 'blob', ($Commit + ':' + $path))) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $ms = [IO.MemoryStream]::new(); $p.StandardOutput.BaseStream.CopyTo($ms); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw ('git cat-file ' + $Commit.Substring(0, 7) + ':' + $path + ' — ' + $err.Trim()) }
  , $ms.ToArray()
}
function Get-BytesSha([byte[]]$b) { ([Security.Cryptography.SHA256]::HashData($b) | ForEach-Object { $_.ToString('x2') }) -join '' }
$base = 'episodes/EP003/'
$plan = Get-Blob ($base + 'plan.json')
if ((Get-BytesSha $plan) -ne $PlanSha) { throw ('plan.json коммита ' + $Commit + ' не совпал с зафиксированным SHA-256.') }
$pj = [Text.Encoding]::UTF8.GetString($plan).TrimStart([char]0xFEFF) | ConvertFrom-Json -AsHashtable
if ($pj.existing_opening.sha256 -ne $OpeningSha -or $pj.existing_opening.last_frame_sha256 -ne $OpeningLastSha) { throw 'SHA-256 начала в plan.json не совпали с зафиксированными в ep003_lib.ps1.' }
$files = @('assemble-with-audio.ffmpeg.txt', 'README.md', 'CLAUDE_PRODUCE_FULL_RU.md') + @(foreach ($t in @($pj.image_tasks) + @($pj.video_tasks)) { $t.prompt_file })
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
[IO.File]::WriteAllBytes((Join-Path $Dest 'plan.json'), $plan)
$out = [ordered]@{ 'plan.json' = (Get-BytesSha $plan) }
foreach ($f in $files) {
  $b = Get-Blob ($base + $f)
  $t = @(@($pj.image_tasks) + @($pj.video_tasks) | Where-Object { $_.prompt_file -eq $f })
  if ($t.Count -eq 1 -and (Get-BytesSha $b) -ne $t[0].prompt_sha256) { throw ('Промпт ' + $f + ' не совпал с plan.json.') }
  if ($f -eq 'assemble-with-audio.ffmpeg.txt' -and (Get-BytesSha $b) -ne $FilterSha) { throw 'Фильтр сборки не совпал с зафиксированным SHA-256.' }
  [IO.File]::WriteAllBytes((Join-Path $Dest ($f -replace '/', '__')), $b)
  $out[$f] = Get-BytesSha $b
}
foreach ($bin in @(@('deliverables/ep002/EP002_timing_7s_sound_720p.mp4', 'opening-7s.mp4', $OpeningSha), @(($base + 'references/opening-lastframe.png'), 'opening-lastframe.png', $OpeningLastSha))) {
  $b = Get-Blob $bin[0]
  if ((Get-BytesSha $b) -ne $bin[2]) { throw ('Бинарный файл ' + $bin[0] + ' коммита не совпал с plan.json по SHA-256.') }
  [IO.File]::WriteAllBytes((Join-Path $Dest $bin[1]), $b)
  $out[$bin[0] + ' → ' + $bin[1]] = Get-BytesSha $b
}
'Файлы коммита ' + $Commit.Substring(0, 7) + ' → ' + $Dest + ':'
foreach ($k in $out.Keys) { '  ' + $out[$k] + '  ' + $k }
