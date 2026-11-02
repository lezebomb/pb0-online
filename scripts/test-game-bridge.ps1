$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$backup=(Get-Content -LiteralPath (Join-Path $project 'runs\latest-save-backup.txt') -Raw).Trim()
$manifest=Get-Content -LiteralPath (Join-Path $backup 'manifest.json') -Raw | ConvertFrom-Json
$guards=@()
try {
  # Keep every original save file read-only to other processes for the entire test, without changing ACLs/attributes.
  foreach($f in $manifest.Files) {$guards+=[IO.File]::Open($f.Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}
  Push-Location $project
  try {node scripts/test-game-bridge.mjs; $result=$LASTEXITCODE} finally {Pop-Location}
} finally {foreach($guard in $guards){$guard.Dispose()}}
$changed=@($manifest.Files | Where-Object {(Get-FileHash -LiteralPath $_.Source -Algorithm SHA256).Hash -ne $_.Sha256})
Write-Output "ORIGINAL_SAVE_GUARD changed=$($changed.Count)"
if($changed.Count) {throw '原存档变化，已停止后续测试。'}
exit $result
