param(
  [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Name='host',
  [string]$GameRoot='D:\SteamLibrary\steamapps\common\PBZ'
)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$destination=Join-Path $project ('game-instances\'+$Name)
if(Test-Path -LiteralPath $destination) {throw "已存在测试目录，不覆盖: $destination"}
$backup=(Get-Content -LiteralPath (Join-Path $project 'runs\latest-save-backup.txt') -Raw).Trim()
$manifest=Get-Content -LiteralPath (Join-Path $backup 'manifest.json') -Raw | ConvertFrom-Json
foreach($f in $manifest.Files) {if((Get-FileHash -LiteralPath $f.Backup -Algorithm SHA256).Hash -ne $f.Sha256) {throw '原存档备份校验失败。'}}
New-Item -ItemType Directory -Path (Join-Path $destination 'platform\steam') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $destination 'ProjectPBZ\Saved\SaveGames') -Force | Out-Null
foreach($file in Get-ChildItem -LiteralPath (Join-Path $GameRoot 'ProjectPBZ') -File) {
  Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $destination 'ProjectPBZ')
}
# Only asset/runtime directories are shared. Saved and the mod/config folders are independent real directories.
foreach($relative in @('Engine','ProjectPBZ\Content','ProjectPBZ\Plugins','ProjectPBZ\Binaries','ProjectPBZ\SteamInput')) {
  $target=Join-Path $GameRoot $relative
  if(Test-Path -LiteralPath $target -PathType Container) {New-Item -ItemType Junction -Path (Join-Path $destination $relative) -Target $target | Out-Null}
}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $GameRoot 'platform\steam') -File) {
  # Copy executable/runtime files unchanged; no binary patches and no links to writable original saves.
  Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $destination 'platform\steam')
}
if(Test-Path -LiteralPath (Join-Path $GameRoot 'platform\steam\D3D12')) {
  New-Item -ItemType Junction -Path (Join-Path $destination 'platform\steam\D3D12') -Target (Join-Path $GameRoot 'platform\steam\D3D12') | Out-Null
}
Copy-Item -LiteralPath (Join-Path $GameRoot 'platform\steam\ue4ss') -Destination (Join-Path $destination 'platform\steam') -Recurse
Copy-Item -LiteralPath (Join-Path $GameRoot 'steam_api64.dll') -Destination $destination
# Steam's standard development app-ID file prevents the original API from relaunching through the installed path.
# Entitlement and DRM remain handled by the original game and Steam API; no authentication code is changed.
[IO.File]::WriteAllText((Join-Path $destination 'platform\steam\steam_appid.txt'),'4115450')
$testProgress=Get-ChildItem -LiteralPath (Join-Path $project 'backups') -Directory -Filter 'test-progress-*' | Sort-Object Name -Descending | Select-Object -First 1
if($testProgress) {
  foreach($entry in Get-ChildItem -LiteralPath (Join-Path $testProgress.FullName 'SaveGames') -Force) {
    Copy-Item -LiteralPath $entry.FullName -Destination (Join-Path $destination 'ProjectPBZ\Saved\SaveGames') -Recurse
  }
}
$receipt=[ordered]@{Name=$Name;Root=$destination;Source=$GameRoot;OriginalBackup=$backup;SaveDirectory=Join-Path $destination 'ProjectPBZ\Saved\SaveGames';SaveIsolationVerifiedInGame=$false}
$receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'pb0-test-profile.json') -Encoding UTF8
Write-Output "TEST_PROFILE_PREPARED $destination (runtime save path still needs verification)"
