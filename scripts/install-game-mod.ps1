param([string]$GameRoot='D:\SteamLibrary\steamapps\common\PBZ')
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue) {throw '请先关闭游戏。'}
$backupPointer=Join-Path $project 'runs\latest-save-backup.txt'
if(!(Test-Path -LiteralPath $backupPointer)) {throw '请先运行 backup-game-saves.ps1。'}
$backup=(Get-Content -LiteralPath $backupPointer -Raw).Trim()
$manifest=Get-Content -LiteralPath (Join-Path $backup 'manifest.json') -Raw | ConvertFrom-Json
if(!$manifest.Verified -or @($manifest.Files).Count -eq 0) {throw '存档备份未验证。'}
foreach($file in $manifest.Files) {
  if((Get-FileHash -LiteralPath $file.Backup -Algorithm SHA256).Hash -ne $file.Sha256) {throw '存档备份哈希不匹配。'}
}
$target=Join-Path $GameRoot 'platform\steam'
if(!(Test-Path -LiteralPath (Join-Path $target 'PBZ.exe'))) {throw '未找到正版游戏程序。'}
if(Test-Path -LiteralPath (Join-Path $target 'dwmapi.dll')) {throw '已有 UE4SS/其他 dwmapi.dll，不覆盖现有安装。'}
if(Test-Path -LiteralPath (Join-Path $target 'ue4ss')) {throw '已有 ue4ss 目录，不覆盖现有安装。'}
$stage=Join-Path $project 'tools\pbz-ue4ss'
$pact=Join-Path $project 'tools\phantom-pact-release\platform\steam\ue4ss\Mods\PBZCoop'
if(!(Test-Path -LiteralPath (Join-Path $stage 'dwmapi.dll')) -or !(Test-Path -LiteralPath (Join-Path $pact 'dlls\main.dll'))) {throw '缺少已校验的官方发布包。'}
$installed=@()
function Install-Tree([string]$Source,[string]$Destination) {
  foreach($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
    $relative=$file.FullName.Substring($Source.TrimEnd('\').Length+1)
    $dest=Join-Path $Destination $relative
    if(Test-Path -LiteralPath $dest) {throw "不覆盖已有文件: $dest"}
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $dest
    $script:installed += $dest
  }
}
Install-Tree $stage $target
$modRoot=Join-Path $target 'ue4ss\Mods\PBZCoop'
Install-Tree $pact $modRoot
$mods=Join-Path $target 'ue4ss\Mods\mods.txt'
$text=Get-Content -LiteralPath $mods -Raw
$text=$text -replace '(?m)^(\w+)\s*:\s*1\s*$', '$1 : 0'
$text="PBZCoop : 1`r`n"+$text
[IO.File]::WriteAllText($mods,$text)
$ini=Join-Path $modRoot 'PhantomPact.ini'
[IO.File]::WriteAllText($ini,((Get-Content -LiteralPath $ini -Raw) -replace '(?m)^Role\s*=.*$','Role = Off'))
$receipt=[ordered]@{GameRoot=$GameRoot;SaveBackup=$backup;UE4SS='v3.0.1-1195-g1ceefac8';PhantomPact='1.4.1';Files=@()}
foreach($file in $installed) {$receipt.Files+=@{Path=$file;Sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}}
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $project 'runs\mod-install.json') -Encoding UTF8
Write-Output "MOD_INSTALLED files=$($installed.Count) saveBackup=$backup"
