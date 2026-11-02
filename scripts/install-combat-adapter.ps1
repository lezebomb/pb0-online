#requires -Version 7.0
param([ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Name='host')
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $project ('game-instances\'+$Name)
if(!(Test-Path -LiteralPath (Join-Path $root 'pb0-test-profile.json'))){throw '只为已准备的隔离测试副本安装。'}
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue){throw '请先关闭游戏。'}
$mods=Join-Path $root 'platform\steam\ue4ss\Mods'
$file=Join-Path $mods 'PBZCoop\Scripts\pvp.lua'
$release=Join-Path $project 'tools\phantom-pact-release\platform\steam\ue4ss\Mods\PBZCoop\Scripts\pvp.lua'
$base=[IO.File]::ReadAllText($release)
$needle='if swing.guarded and not swing.spoiled and near then'
$replacement='if not rawget(_G, "PB0_NATIVE_PVP") and swing.guarded and not swing.spoiled and near then'
if(!$base.Contains($needle)){throw '未识别的 Phantom Pact 发布版本。'}
$patched=$base.Replace($needle,$replacement)
$current=[IO.File]::ReadAllText($file)
if($current -ne $base -and $current -ne $patched){throw '现有 PvP 文件有其他修改，不覆盖。'}
$backup=Join-Path $project ('backups\combat-adapter-'+$Name+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item -LiteralPath $file -Destination (Join-Path $backup 'pvp.lua')
$modsFile=Join-Path $mods 'mods.txt'
Copy-Item -LiteralPath $modsFile -Destination (Join-Path $backup 'mods.txt')
[IO.File]::WriteAllText($file,$patched)
# Load in Phantom Pact's Lua state, where PBZ and its callbacks live.
$main=Join-Path $mods 'PBZCoop\Scripts\main.lua'
$baseMain=[IO.File]::ReadAllText((Join-Path $project 'tools\phantom-pact-release\platform\steam\ue4ss\Mods\PBZCoop\Scripts\main.lua'))
$anchor='-- Command file: lets a developer drive tests from outside the game.'
$mainPatch=$baseMain.Replace($anchor,'dofile(modRoot() .. "../PB0CombatAdapter/Scripts/main.lua")'+"`r`n`r`n"+$anchor)
$oldMain=[IO.File]::ReadAllText($main)
if($oldMain -ne $baseMain -and $oldMain -ne $mainPatch){throw '现有 main.lua 有其他修改，不覆盖。'}
Copy-Item -LiteralPath $main -Destination (Join-Path $backup 'main.lua')
[IO.File]::WriteAllText($main,$mainPatch)
$target=Join-Path $mods 'PB0CombatAdapter\Scripts'
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'src\Pb0.Mod\Scripts\main.lua') -Destination (Join-Path $target 'main.lua') -Force
$text=[IO.File]::ReadAllText($modsFile)
if($text -notmatch '(?m)^PB0CombatAdapter\s*:'){$text="PB0CombatAdapter : 0`r`n"+$text}else{$text=[regex]::Replace($text,'(?m)^PB0CombatAdapter\s*:.*$','PB0CombatAdapter : 0')}
[IO.File]::WriteAllText($modsFile,$text)
$autoEnable=Join-Path (Split-Path $target -Parent) 'enabled.txt'
if(Test-Path -LiteralPath $autoEnable){Remove-Item -LiteralPath $autoEnable}
@{Version=1;GameRoot=$root;SourceBackup=$backup;HeuristicDisabledOnlyWhileAdapterActive=$true;Installed=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'pb0-combat-adapter.json') -Encoding UTF8
Write-Output "COMBAT_ADAPTER_INSTALLED $Name (only isolated copy modified)"
