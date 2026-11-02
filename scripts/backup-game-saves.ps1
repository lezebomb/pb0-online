param(
  [string]$GameRoot='D:\SteamLibrary\steamapps\common\PBZ',
  [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference='Stop'
if (Get-Process -Name PBZ -ErrorAction SilentlyContinue) { throw '请先关闭正在运行的游戏，避免备份到写入中的存档。' }
$sources=[ordered]@{}
$candidates=[ordered]@{
  GameSave=Join-Path $GameRoot 'ProjectPBZ\Saved\SaveGames'
  UserSave=Join-Path $env:LOCALAPPDATA 'ProjectPBZ\Saved\SaveGames'
}
foreach($key in $candidates.Keys) {
  if (Test-Path -LiteralPath $candidates[$key] -PathType Container -ErrorAction Stop) { $sources[$key]=$candidates[$key] }
}
$steamUserdata='C:\Program Files (x86)\Steam\userdata'
if (Test-Path -LiteralPath $steamUserdata -PathType Container -ErrorAction Stop) {
  foreach($account in Get-ChildItem -LiteralPath $steamUserdata -Directory -ErrorAction Stop) {
    $remote=Join-Path $account.FullName '4115450\remote'
    if(Test-Path -LiteralPath $remote -PathType Container -ErrorAction Stop) { $sources['Steam-'+$account.Name]=$remote }
  }
}
if ($sources.Count -eq 0) { throw '未找到原存档，已停止；不会启动游戏。' }
$backup=Join-Path $ProjectRoot ('backups\saves-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$files=@()
$totalBytes=0L
foreach($label in $sources.Keys) {
  $source=[IO.Path]::GetFullPath($sources[$label]).TrimEnd('\')
  foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse -Force -ErrorAction Stop) {
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "拒绝跟随存档中的链接: $($file.FullName)" }
    $relative=$file.FullName.Substring($source.Length+1)
    $target=Join-Path (Join-Path $backup $label) $relative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    $originalHash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
    Copy-Item -LiteralPath $file.FullName -Destination $target -ErrorAction Stop
    if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $originalHash) { throw "备份校验失败: $relative" }
    $files += [ordered]@{Source=$file.FullName;Backup=$target;Length=$file.Length;Sha256=$originalHash}
    $totalBytes+=$file.Length
  }
}
if($files.Count -eq 0) { throw '存档目录为空，已停止；不会启动游戏。' }
$manifest=[ordered]@{Version=1;Verified=$true;Created=(Get-Date).ToString('o');Files=$files}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
New-Item -ItemType Directory -Path (Join-Path $ProjectRoot 'runs') -Force | Out-Null
$backup | Set-Content -LiteralPath (Join-Path $ProjectRoot 'runs\latest-save-backup.txt') -Encoding UTF8
Write-Output "SAVE_BACKUP_VERIFIED files=$($files.Count) bytes=$totalBytes path=$backup"
