#requires -Version 7.0
param([Parameter(Mandatory)][ValidateSet('Play','Test')][string]$Mode)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$stateFile=Join-Path $project 'runs\save-profile-state.json'
if(!(Test-Path -LiteralPath $stateFile)){throw '缺少存档切换状态；先确认个人与测试备份，不能猜测恢复来源。'}
$state=Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -AsHashtable
$original='D:\SteamLibrary\steamapps\common\PBZ\ProjectPBZ\Saved\SaveGames'
$test=Join-Path $project 'game-instances\host\ProjectPBZ\Saved\SaveGames'
$guest=Join-Path $project 'game-instances\guest\ProjectPBZ\Saved\SaveGames'
$backupRoot=[IO.Path]::GetFullPath((Join-Path $project 'backups')).TrimEnd('\')
if($state.OriginalSaveRoot -ne $original -or $state.TestSaveRoot -ne $test){throw '存档根目录与本项目不符，停止切换。'}
if($state.ActiveMode -eq $Mode){Write-Output "SAVE_MODE_ALREADY_$($Mode.ToUpperInvariant()) (不回滚当前进度)";return}
if($state.ActiveMode -notin @('Play','Test')){throw '上一次切换未完成，先根据备份与状态核对，不能自动覆盖。'}
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue){throw '游戏仍运行。请先正常退出游戏；不会结束个人游戏或覆盖正在写入的存档。'}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$session=Join-Path $backupRoot ('save-switch-'+$stamp)
New-Item -ItemType Directory -Path $session | Out-Null
function Save-State {
    $state.Updated=(Get-Date).ToString('o')
    $tmp=$stateFile+'.tmp'
    [IO.File]::WriteAllText($tmp,($state | ConvertTo-Json -Depth 8))
    Move-Item -LiteralPath $tmp -Destination $stateFile -Force
}
function Assert-Backup([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    if(!$full.StartsWith($backupRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw '备份不在本项目 backups 目录。'}
    if(!(Test-Path -LiteralPath $full -PathType Container)){throw '备份目录不存在。'}
    if((Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '拒绝使用链接作为备份目录。'}
}
function Safe-Child([string]$Root,[string]$Relative) {
    $full=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if([IO.Path]::IsPathRooted($Relative) -or !$full.StartsWith(([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw '存档相对路径越界。'}
    return $full
}
function Backup-Tree([string]$Source,[string]$Label) {
    $Source=[IO.Path]::GetFullPath($Source).TrimEnd('\')
    if(!(Test-Path -LiteralPath $Source -PathType Container)){throw "存档目录不存在: $Source"}
    if((Get-Item -LiteralPath $Source).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '存档目录不能是链接。'}
    $target=Join-Path $session $Label
    New-Item -ItemType Directory -Path $target | Out-Null
    $files=@()
    foreach($entry in Get-ChildItem -LiteralPath $Source -Recurse -Force){
        if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '存档包含链接，停止。'}
        if($entry.PSIsContainer){continue}
        $relative=$entry.FullName.Substring($Source.Length+1)
        $copy=Safe-Child $target $relative
        New-Item -ItemType Directory -Path (Split-Path $copy -Parent) -Force | Out-Null
        $hash=(Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $entry.FullName -Destination $copy
        if((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $hash -or (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash -ne $hash){throw '备份时文件变化或校验失败。'}
        $files+=@{Relative=$relative;Sha256=$hash;Length=$entry.Length}
    }
    @{Version=1;Verified=$true;Source=$Source;Created=(Get-Date).ToString('o');Files=$files} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $target 'pb0-snapshot.json') -Encoding UTF8
    return $target
}
function Read-TestTree([string]$Snapshot) {
    Assert-Backup $Snapshot
    $m=Get-Content -LiteralPath (Join-Path $Snapshot 'pb0-snapshot.json') -Raw | ConvertFrom-Json
    if(!$m.Verified -or !$m.Files.Count){throw '测试存档备份为空或未经校验。'}
    return @($m.Files | ForEach-Object {@{Relative=$_.Relative;Backup=(Safe-Child $Snapshot $_.Relative);Sha256=$_.Sha256}})
}
function Personal-Trees([string]$Snapshot) {
    Assert-Backup $Snapshot
    $m=Get-Content -LiteralPath (Join-Path $Snapshot 'manifest.json') -Raw | ConvertFrom-Json
    if(!$m.Verified -or !$m.Files.Count){throw '个人存档备份为空或未经校验。'}
    $groups=@{}
    foreach($f in $m.Files){
        $source=[IO.Path]::GetFullPath($f.Source)
        $root=$null
        foreach($candidate in @($original,(Join-Path $env:LOCALAPPDATA 'ProjectPBZ\Saved\SaveGames'))){
            if($source.StartsWith($candidate+'\',[StringComparison]::OrdinalIgnoreCase)){$root=$candidate;break}
        }
        if(!$root -and $source -match '^(C:\\Program Files \(x86\)\\Steam\\userdata\\\d+\\4115450\\remote)\\'){$root=$Matches[1]}
        if(!$root){throw "个人备份含未识别的恢复位置: $source"}
        $relative=$source.Substring($root.Length+1)
        $backup=[IO.Path]::GetFullPath($f.Backup)
        if(!$backup.StartsWith(([IO.Path]::GetFullPath($Snapshot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw '备份文件越界。'}
        if(!$groups.ContainsKey($root)){$groups[$root]=@()}
        $groups[$root]+=@{Relative=$relative;Backup=$backup;Sha256=$f.Sha256}
    }
    return $groups
}
function Restore-Tree([string]$Destination,[array]$Files) {
    # Only save directories discovered above, never an installation or asset directory.
    $Destination=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
    $allowed=$Destination -eq $original -or $Destination -eq $test -or $Destination -eq $guest -or $Destination -eq (Join-Path $env:LOCALAPPDATA 'ProjectPBZ\Saved\SaveGames') -or $Destination -match '^C:\\Program Files \(x86\)\\Steam\\userdata\\\d+\\4115450\\remote$'
    if(!$allowed -or !$Files.Count){throw '恢复目标或文件清单无效。'}
    foreach($file in $Files){
        $null=Safe-Child $Destination $file.Relative
        if((Get-FileHash -LiteralPath $file.Backup -Algorithm SHA256).Hash -ne $file.Sha256){throw '恢复源校验失败，未改动当前存档。'}
    }
    $stage=$Destination+'.pb0-stage-'+$stamp
    $rollback=$Destination+'.pb0-before-'+$stamp
    if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $rollback)){throw '切换临时目录已存在，停止。'}
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    foreach($file in $Files){
        $target=Safe-Child $stage $file.Relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $file.Backup -Destination $target
        if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $file.Sha256){throw '暂存副本校验失败。'}
    }
    $hadOld=Test-Path -LiteralPath $Destination
    if($hadOld){
        if((Get-Item -LiteralPath $Destination).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '恢复目标不能是链接。'}
        Move-Item -LiteralPath $Destination -Destination $rollback
    }
    try {Move-Item -LiteralPath $stage -Destination $Destination} catch {if($hadOld){Move-Item -LiteralPath $rollback -Destination $Destination};throw}
    $actual=@(Get-ChildItem -LiteralPath $Destination -File -Recurse -Force)
    if($actual.Count -ne $Files.Count){throw '恢复后的文件数量不符，保留所有副本。'}
    foreach($file in $Files){if((Get-FileHash -LiteralPath (Safe-Child $Destination $file.Relative) -Algorithm SHA256).Hash -ne $file.Sha256){throw '恢复后哈希不符，保留所有副本。'}}
    Write-Output "SAVE_TREE_VERIFIED files=$($Files.Count) path=$Destination"
}
# Validate the incoming profile before archiving or changing the active profile.
$personalTrees=Personal-Trees $state.PersonalBackup
$testFiles=Read-TestTree $state.TestBackup
if($Mode -eq 'Test'){
    & (Join-Path $PSScriptRoot 'backup-game-saves.ps1')
    $state.PersonalBackup=(Get-Content -LiteralPath (Join-Path $project 'runs\latest-save-backup.txt') -Raw).Trim()
    $state.TestBeforeSwitchBackup=Backup-Tree $test 'test-before-switch'
    if(Test-Path -LiteralPath $guest){$state.GuestBeforeSwitchBackup=Backup-Tree $guest 'guest-before-switch'}
    $state.ActiveMode='SwitchingToTest';$state.TestingPaused=$true;Save-State
    Restore-Tree $original $testFiles
    Restore-Tree $test $testFiles
    if($state.GuestTestBackup -and (Test-Path -LiteralPath $guest)){Restore-Tree $guest (Read-TestTree $state.GuestTestBackup)}
    $state.ActiveMode='Test';$state.TestingPaused=$false
}else{
    $state.BeforePlayBackup=Backup-Tree $original 'active-before-play'
    $state.TestBackup=Backup-Tree $test 'test-save'
    if(Test-Path -LiteralPath $guest){$state.GuestTestBackup=Backup-Tree $guest 'test-guest-save'}
    $userData=Join-Path $project 'game-instances\host\user-data'
    if(Test-Path -LiteralPath $userData){$state.TestUserDataBackup=Backup-Tree $userData 'test-user-data'}
    $state.ActiveMode='SwitchingToPlay';$state.TestingPaused=$true;Save-State
    foreach($destination in $personalTrees.Keys){Restore-Tree $destination $personalTrees[$destination]}
    $state.ActiveMode='Play';$state.TestingPaused=$true
}
Save-State
$state.PersonalBackup | Set-Content -LiteralPath (Join-Path $project 'runs\latest-save-backup.txt') -Encoding UTF8
Write-Output "SAVE_MODE_$($Mode.ToUpperInvariant()) (游戏未启动；备份均保留)"
