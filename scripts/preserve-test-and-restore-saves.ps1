$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$gameRoot='D:\SteamLibrary\steamapps\common\PBZ'
$gameExe=Join-Path $gameRoot 'platform\steam\PBZ.exe'
foreach($p in Get-Process -Name PBZ -ErrorAction SilentlyContinue) {
  if($p.Path -eq $gameExe) {try {$null=$p.WaitForExit(10000)} catch {}}
}
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $gameExe}) {throw '游戏仍运行，暂不覆盖任何存档。'}
$backup=(Get-Content -LiteralPath (Join-Path $project 'runs\latest-save-backup.txt') -Raw).Trim()
$m=Get-Content -LiteralPath (Join-Path $backup 'manifest.json') -Raw | ConvertFrom-Json
$testCopy=Join-Path $project ('backups\test-progress-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $testCopy -Force | Out-Null
$source=Join-Path $gameRoot 'ProjectPBZ\Saved\SaveGames'
Copy-Item -LiteralPath $source -Destination $testCopy -Recurse
foreach($file in $m.Files) {
  if((Get-FileHash -LiteralPath $file.Backup -Algorithm SHA256).Hash -ne $file.Sha256) {throw '原始备份校验失败，已停止。'}
}
foreach($file in $m.Files) {
  if(!(Test-Path -LiteralPath $file.Source) -or (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256).Hash -ne $file.Sha256) {
    New-Item -ItemType Directory -Path (Split-Path $file.Source -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.Backup -Destination $file.Source -Force
  }
}
$bad=@($m.Files | Where-Object {!(Test-Path -LiteralPath $_.Source) -or (Get-FileHash -LiteralPath $_.Source -Algorithm SHA256).Hash -ne $_.Sha256})
if($bad.Count) {throw '原存档还原后校验失败。'}
@{RestoredOriginalFiles=$m.Files.Count;AllOriginalHashesMatch=$true;OriginalBackup=$backup;TestProgress=$testCopy} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project 'runs\save-restored.json') -Encoding UTF8
Write-Output "ORIGINAL_SAVES_RESTORED_AND_VERIFIED files=$($m.Files.Count) testCopy=$testCopy"
