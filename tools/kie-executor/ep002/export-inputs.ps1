# export-inputs.ps1 — бесплатно и без сети: достаёт из локального git точные файлы зафиксированного коммита пакета EP002
# ($Commit из ep002_lib.ps1): plan.json, фильтр сборки, пять промптов, README.md и карточку CLAUDE_PRODUCE_FULL_RU.md.
# prompts/K0-effort.prompt.en.txt → prompts__K0-effort.prompt.en.txt. Папка по умолчанию inputs/ (в .gitignore).
param([string]$Dest = (Join-Path $PSScriptRoot 'inputs'))
. (Join-Path $PSScriptRoot 'ep002_lib.ps1')
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
$base = 'episodes/EP002/'
$plan = Get-Blob ($base + 'plan.json')
if ((Get-BytesSha $plan) -ne $PlanSha) { throw ('plan.json коммита ' + $Commit + ' не совпал с зафиксированным SHA-256.') }
$pj = [Text.Encoding]::UTF8.GetString($plan).TrimStart([char]0xFEFF) | ConvertFrom-Json -AsHashtable
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
'Файлы коммита ' + $Commit.Substring(0, 7) + ' → ' + $Dest + ':'
foreach ($k in $out.Keys) { '  ' + $out[$k] + '  ' + $k }
