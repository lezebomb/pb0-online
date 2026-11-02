#requires -Version 7.0
param([switch]$Dual,[ValidateRange(60,900)][int]$Seconds=300)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue){throw '请先正常退出正在运行的游戏，避免影响游玩存档。'}
& (Join-Path $PSScriptRoot 'switch-save-profile.ps1') -Mode Test
$nodeArgs=@('--stage','movement','--demo','--timeout','120','--session-seconds',$Seconds.ToString())
$entry=if($Dual){'scripts/test-dual-game.mjs'}else{'scripts/test-game-bridge.mjs'}
$code=1
try {
  & (Join-Path $PSScriptRoot 'install-combat-adapter.ps1') -Name host
  if($Dual){& (Join-Path $PSScriptRoot 'install-combat-adapter.ps1') -Name guest}
  Write-Output '使用隔离测试存档；模拟对手每 2.5 秒主动攻击。Ctrl+C 结束；到时自动退出。'
  Write-Output '单进程入口用于来袭、防御和弹反演示；双向真实伤害用双真实进程验收入口。'
  Push-Location $project
  try {node $entry @nodeArgs;$code=$LASTEXITCODE} finally {Pop-Location}
} finally {
  # The launcher owns its game through a Windows Job; wait for cleanup before switching saves.
  $end=(Get-Date).AddSeconds(8)
  while((Get-Date) -lt $end -and (Get-Process -Name PBZ -ErrorAction SilentlyContinue)){Start-Sleep -Milliseconds 200}
  if(!(Get-Process -Name PBZ -ErrorAction SilentlyContinue)){
    & (Join-Path $PSScriptRoot 'switch-save-profile.ps1') -Mode Play
  } else {Write-Warning '仍有游戏运行，未切换存档；已保留个人与测试备份。'}
}
exit $code
