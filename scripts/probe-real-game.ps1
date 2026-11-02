param([string]$GameRoot='D:\SteamLibrary\steamapps\common\PBZ',[int]$Seconds=40)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $GameRoot 'platform\steam\PBZ.exe'
$run=Join-Path $project ('runs\game-probe-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$backup=(Get-Content -LiteralPath (Join-Path $project 'runs\latest-save-backup.txt') -Raw).Trim()
$manifest=Get-Content -LiteralPath (Join-Path $backup 'manifest.json') -Raw | ConvertFrom-Json
if(!$manifest.Verified) {throw '缺少已验证存档备份。'}
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue) {throw '已有游戏进程，停止启动。'}
# Launch the original executable directly; there is no DRM patch or Steam account manipulation.
$info=[Diagnostics.ProcessStartInfo]::new($exe)
$info.WorkingDirectory=Split-Path $exe -Parent
$info.UseShellExecute=$false
foreach($arg in @('ProjectPBZ',('-basedir='+(Join-Path $GameRoot 'ProjectPBZ\Binaries\Win64')),'-pc-platform=Steam','-allowmultipleinstances','-windowed','-ResX=960','-ResY=540','-nosplash',('-UserDir='+(Join-Path $run 'game-user')),'-ExecCmds=sg.ViewDistanceQuality 0,sg.ShadowQuality 0,sg.PostProcessQuality 0,sg.EffectsQuality 0,sg.FoliageQuality 0')) {
  [void]$info.ArgumentList.Add($arg)
}
$game=[Diagnostics.Process]::Start($info)
@{Pid=$game.Id;Exe=$exe;Run=$run;SaveBackup=$backup} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project 'runs\game-probe-current.json') -Encoding UTF8
Write-Output "GAME_DIRECT_STARTED pid=$($game.Id) run=$run"
if($game.WaitForExit($Seconds*1000)) {Write-Output "GAME_EXITED code=$($game.ExitCode)"}
else {Write-Output "GAME_RUNNING pid=$($game.Id)"}
# Leave a running game available for UI inspection. The script never kills unrelated game processes.
$log=Join-Path $GameRoot 'platform\steam\ue4ss\UE4SS.log'
if(Test-Path -LiteralPath $log) {
  Copy-Item -LiteralPath $log -Destination (Join-Path $run 'UE4SS.log')
  Select-String -LiteralPath $log -Pattern '\[PBZCoop\].*Loaded|Error loading|Error executing|Lua.*error' | Select-Object -Last 10 | ForEach-Object {$_.Line}
}
$changed=@()
foreach($file in $manifest.Files) {
  if(!(Test-Path -LiteralPath $file.Source) -or (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256).Hash -ne $file.Sha256) {$changed+=$file.Source}
}
@{OriginalSaveFilesChanged=$changed;BackupVerified=$true;Run=$run} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $run 'save-check.json') -Encoding UTF8
Write-Output "SAVE_CHECK changedOriginalFiles=$($changed.Count) backupIntact=True"
