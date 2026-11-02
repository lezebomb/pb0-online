param([ValidateSet('movement','pvp')][string]$Stage='pvp',[switch]$Hold,[switch]$Demo,[int]$Timeout=240,[ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Name='host',[switch]$Dual,[ValidateRange(60,900)][int]$SessionSeconds=300)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$saveState=Join-Path $project 'runs\save-profile-state.json'
if(!(Test-Path -LiteralPath $saveState) -or (Get-Content -LiteralPath $saveState -Raw | ConvertFrom-Json).ActiveMode -ne 'Test') {throw '当前为个人游玩模式。用户明确要求测试后，先运行 scripts/switch-save-profile.ps1 -Mode Test 备份个人进度并切换测试存档。'}
$profile=Get-Content -LiteralPath $saveState -Raw | ConvertFrom-Json
$personal=Get-Content -LiteralPath (Join-Path $profile.PersonalBackup 'manifest.json') -Raw | ConvertFrom-Json
foreach($file in $personal.Files){if((Get-FileHash -LiteralPath $file.Backup -Algorithm SHA256).Hash -ne $file.Sha256){throw '个人存档备份校验失败，不启动测试。'}}
# The user explicitly swaps the active installation to the test profile; guard that baseline.
$test=Get-Content -LiteralPath (Join-Path $profile.TestBackup 'pb0-snapshot.json') -Raw | ConvertFrom-Json
$manifest=[pscustomobject]@{Files=@($test.Files | ForEach-Object {[pscustomobject]@{Source=(Join-Path $profile.OriginalSaveRoot $_.Relative);Sha256=$_.Sha256}})}
$guards=@()
try {
  foreach($f in $manifest.Files) {$guards+=[IO.File]::Open($f.Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}
  $options=@('--stage',$Stage,'--timeout',$Timeout.ToString(),'--profile',$Name,'--session-seconds',$SessionSeconds.ToString())
  if($Hold){$options+='--hold'}
  if($Demo){$options+='--demo'}
  Push-Location $project
  $entry=if($Dual){'scripts/test-dual-game.mjs'}else{'scripts/test-game-bridge.mjs'}
  try {node $entry @options;$result=$LASTEXITCODE} finally {Pop-Location}
} finally {foreach($guard in $guards){$guard.Dispose()}}
$changed=@($manifest.Files | Where-Object {(Get-FileHash -LiteralPath $_.Source -Algorithm SHA256).Hash -ne $_.Sha256})
Write-Output "ACTIVE_SAVE_GUARD changed=$($changed.Count)"
if($changed.Count){throw '活动存档变化，已停止后续测试。'}
exit $result
