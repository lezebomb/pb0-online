param([switch]$FrameworkDependent)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$env:DOTNET_CLI_HOME=Join-Path $project 'tools\dotnet-home'
$env:NUGET_PACKAGES=Join-Path $project 'tools\nuget'
$env:APPDATA=Join-Path $project 'tools\build-appdata'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
Push-Location $project
try {
  if($FrameworkDependent) {
    dotnet restore src/Pb0.Launcher/Pb0.Launcher.csproj --configfile NuGet.Config --nologo
  } else {
    node scripts/fetch-dotnet-runtime.mjs
    if($LASTEXITCODE -ne 0) {throw 'Runtime download failed'}
    dotnet restore src/Pb0.Launcher/Pb0.Launcher.csproj -r win-x64 -p:SelfContained=true --configfile NuGet.Config --source downloads/nuget --nologo
  }
  if($LASTEXITCODE -ne 0) {throw 'Restore failed'}
  if($FrameworkDependent) {
    dotnet publish src/Pb0.Launcher/Pb0.Launcher.csproj -c Release --no-restore -o dist/PB0 --nologo
  } else {
    dotnet publish src/Pb0.Launcher/Pb0.Launcher.csproj -c Release -r win-x64 --self-contained true --no-restore -o dist/PB0 --nologo
  }
  if($LASTEXITCODE -ne 0) {throw 'Publish failed'}
  $core=Join-Path $project 'tools\easytier\easytier-windows-x86_64'
  $dest=Join-Path $project 'dist\PB0\tools\easytier\easytier-windows-x86_64'
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  foreach($file in @('easytier-core.exe','easytier-cli.exe')) {Copy-Item -LiteralPath (Join-Path $core $file) -Destination $dest -Force}
  Copy-Item -LiteralPath (Join-Path $project 'README.md') -Destination (Join-Path $project 'dist\PB0') -Force
  Copy-Item -LiteralPath (Join-Path $project 'licenses') -Destination (Join-Path $project 'dist\PB0') -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $project 'Start-PB0.cmd') -Destination (Join-Path $project 'dist\PB0') -Force
  Write-Output "Ready: dist\PB0\PB0.exe (self-contained=$(!$FrameworkDependent))"
} finally {Pop-Location}
