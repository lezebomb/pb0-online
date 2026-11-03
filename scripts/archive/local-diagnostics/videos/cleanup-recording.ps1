#requires -Version 7.0
$ErrorActionPreference='Stop'
$project='D:\pb0online'
$run=(Get-Content -LiteralPath (Join-Path $project 'runs\dual-game-current.json') -Raw | ConvertFrom-Json).run
if($run.StartsWith((Join-Path $project 'runs\record-game-'),[StringComparison]::OrdinalIgnoreCase)){
 [IO.File]::WriteAllText((Join-Path $run 'stop'),'End this recording session and release owned games.')
}
$deadline=(Get-Date).AddSeconds(8)
while((Get-Date) -lt $deadline -and (Get-Process -Name PBZ -ErrorAction SilentlyContinue)){Start-Sleep -Milliseconds 200}
$owned=Get-CimInstance Win32_Process -Filter "Name='PB0.exe'" | Where-Object {$_.ExecutablePath -eq 'D:\pb0online\dist\PB0\PB0.exe' -and $_.CommandLine.Contains($run)}
foreach($p in $owned){Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue}
$obs=Get-Content -LiteralPath (Join-Path $project 'runs\videos\obs-process.json') -Raw | ConvertFrom-Json
$p=Get-CimInstance Win32_Process -Filter "ProcessId=$($obs.Pid)"
if($p -and $p.ExecutablePath -eq $obs.Exe){Stop-Process -Id $obs.Pid -Force}
Start-Sleep -Milliseconds 600
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue){throw 'Still a running game; do not replace saves.'}
& (Join-Path $project 'scripts\switch-save-profile.ps1') -Mode Play
Write-Output 'RECORDING_SESSION_CLEANED_AND_PLAY_RESTORED'