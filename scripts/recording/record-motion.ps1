#requires -Version 7.0
$ErrorActionPreference='Stop'
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$base=Join-Path $project 'runs\videos'
$obsRoot=Join-Path $base 'obs-capture-local'
$obsExe=Join-Path $obsRoot 'bin\64bit\obs64.exe'
$obsPid=$null
$run=$null
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue){throw 'A game is running; will not stop personal play or overwrite saves.'}
if(Get-CimInstance Win32_Process -Filter "Name='obs64.exe'" | Where-Object {$_.ExecutablePath -eq $obsExe}){throw 'Own capture OBS is already running'}
$profile=Join-Path $obsRoot 'config\obs-studio\basic\profiles\PB0Record\basic.ini'
Copy-Item -LiteralPath $profile -Destination (Join-Path $base 'obs-before-quality.ini') -Force
$ini=[IO.File]::ReadAllText($profile)
foreach($pair in @(@('BaseCX','1920'),@('BaseCY','1080'),@('OutputCX','1920'),@('OutputCY','1080'),@('FPSCommon','60'),@('FPSInt','60'),@('FPSNum','60'),@('RecQuality','HQ'),@('RecEncoder','nvenc'),@('FilenameFormatting','PB0-InputSimulation-%CCYY%MM%DD-%hh%mm%ss'))){
 $ini=[regex]::Replace($ini,('(?m)^'+$pair[0]+'=.*$'),($pair[0]+'='+$pair[1]))
}
[IO.File]::WriteAllText($profile,$ini)
$sentinel=Join-Path $obsRoot 'config\obs-studio\.sentinel'
if(Test-Path -LiteralPath $sentinel){
 $resolved=[IO.Path]::GetFullPath($sentinel)
 $archive=[IO.Path]::GetFullPath((Join-Path $base ('obs-session-marker-quality-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))))
 if(!$resolved.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase) -or !$archive.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Marker archive escaped local capture workspace'}
 Move-Item -LiteralPath $resolved -Destination $archive
}
$guestSettings=Join-Path $project 'game-instances\guest\user-data\Saved\Config\Windows\GameUserSettings.ini'
$guestBackup=Join-Path $base 'guest-settings-before-locomotion.ini'
Copy-Item -LiteralPath $guestSettings -Destination $guestBackup -Force
$testSettings=Join-Path $project 'game-instances\host\user-data\Saved\Config\Windows\GameUserSettings.ini'
$testSettingsBackup=Join-Path $base 'test-settings-before-quality.ini'
Copy-Item -LiteralPath $testSettings -Destination $testSettingsBackup -Force
$settings=[IO.File]::ReadAllText($testSettings)
foreach($pair in @(@('FullscreenMode','2'),@('LastConfirmedFullscreenMode','2'),@('PreferredFullscreenMode','2'),@('FrameRateLimit_WhenBackgrounded','240.000000'),@('FrameRateLimit','0.000000'),@('bUseVSync','False'))){
 $settings=[regex]::Replace($settings,('(?m)^'+$pair[0]+'=.*$'),($pair[0]+'='+$pair[1]))
}
[IO.File]::WriteAllText($testSettings,$settings)
$guestText=[IO.File]::ReadAllText($guestSettings)
foreach($pair in @(@('FullscreenMode','2'),@('LastConfirmedFullscreenMode','2'),@('PreferredFullscreenMode','2'),@('FrameRateLimit_WhenBackgrounded','240.000000'),@('FrameRateLimit','0.000000'),@('bUseVSync','False'))){
 $guestText=[regex]::Replace($guestText,('(?m)^'+$pair[0]+'=.*$'),($pair[0]+'='+$pair[1]))
}
[IO.File]::WriteAllText($guestSettings,$guestText)
try{
 & (Join-Path $project 'scripts\switch-save-profile.ps1') -Mode Test
 & (Join-Path $project 'scripts\install-combat-adapter.ps1') -Name host
 & (Join-Path $project 'scripts\install-presentation-sync.ps1') -Name host
 & (Join-Path $project 'scripts\install-combat-adapter.ps1') -Name guest
 & (Join-Path $project 'scripts\install-presentation-sync.ps1') -Name guest
 $obsProcess=Start-Process -FilePath $obsExe -ArgumentList @('--portable','--profile','PB0Record','--collection','PB0Record','--minimize-to-tray','--disable-updater','--disable-missing-files-check','--only-bundled-plugins','--websocket_ipv4_only') -WorkingDirectory (Split-Path $obsExe -Parent) -WindowStyle Hidden -PassThru
 $obsPid=$obsProcess.Id
 @{Pid=$obsPid;Exe=$obsExe} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $base 'quality-obs-process.json')
 $deadline=(Get-Date).AddSeconds(25)
 do{
  Start-Sleep -Milliseconds 300
  $socket=[Net.Sockets.TcpClient]::new()
  try{$socket.Connect('127.0.0.1',49336);$connected=$true}catch{$connected=$false}finally{$socket.Dispose()}
 }while(!$connected -and (Get-Date) -lt $deadline)
 if(!$connected){throw 'Portable OBS websocket did not start'}
 Push-Location $project
 try{node scripts/recording/capture-motion.mjs;$captureCode=$LASTEXITCODE}finally{Pop-Location}
 if($captureCode -ne 0){throw "Quality recording exited $captureCode"}
}finally{
 if(Test-Path -LiteralPath (Join-Path $base 'locomotion-current.json')){
  $run=(Get-Content -LiteralPath (Join-Path $base 'locomotion-current.json') -Raw | ConvertFrom-Json).run
  if($run -and $run.StartsWith((Join-Path $project 'runs\locomotion-game-'),[StringComparison]::OrdinalIgnoreCase)){
   [IO.File]::WriteAllText((Join-Path $run 'stop'),'Finish quality capture and clean this owned session')
   $deadline=(Get-Date).AddSeconds(5)
   while((Get-Date) -lt $deadline -and (Get-Process -Name PBZ -ErrorAction SilentlyContinue)){Start-Sleep -Milliseconds 200}
   $owned=Get-CimInstance Win32_Process -Filter "Name='PB0.exe'" | Where-Object {$_.ExecutablePath -eq (Join-Path $project 'dist\PB0\PB0.exe') -and $_.CommandLine.Contains($run)}
   foreach($p in $owned){Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue}
  }
 }
 if($obsPid){
  $p=Get-CimInstance Win32_Process -Filter "ProcessId=$obsPid"
  if($p -and $p.ExecutablePath -eq $obsExe){Stop-Process -Id $obsPid -Force -ErrorAction SilentlyContinue}
 }
 Start-Sleep -Milliseconds 700
 if(!(Get-Process -Name PBZ -ErrorAction SilentlyContinue)){Copy-Item -LiteralPath $guestBackup -Destination $guestSettings -Force;Copy-Item -LiteralPath $testSettingsBackup -Destination $testSettings -Force;& (Join-Path $project 'scripts\switch-save-profile.ps1') -Mode Play}
 else{Write-Warning 'Running game remains; no save overwrite performed'}
}