$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
Push-Location $project
try {
  if(!(Test-Path -LiteralPath 'tools/easytier/easytier-windows-x86_64/easytier-core.exe')) {
    node scripts/fetch-easytier.mjs
    if($LASTEXITCODE -ne 0) {throw 'EasyTier 下载或校验失败'}
    Expand-Archive -LiteralPath 'downloads/easytier-windows-x86_64-v2.6.4.zip' -DestinationPath 'tools/easytier' -Force
  }
  & (Join-Path $PSScriptRoot 'build.ps1')
} finally {Pop-Location}
