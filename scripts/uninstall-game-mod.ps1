$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$receipt=Get-Content -LiteralPath (Join-Path $project 'runs\mod-install.json') -Raw | ConvertFrom-Json
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue) {throw '请先关闭游戏。'}
$target=[IO.Path]::GetFullPath((Join-Path $receipt.GameRoot 'platform\steam')).TrimEnd('\')+'\'
$kept=@()
foreach($file in $receipt.Files) {
  $resolved=[IO.Path]::GetFullPath($file.Path)
  if(!$resolved.StartsWith($target,[StringComparison]::OrdinalIgnoreCase)) {throw '安装清单路径超出游戏 Mod 目录。'}
  if(Test-Path -LiteralPath $resolved -PathType Leaf) {
    if((Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash -eq $file.Sha256) {Remove-Item -LiteralPath $resolved}
    else {$kept+=$resolved}
  }
}
Write-Output "Mod files removed. Modified files preserved: $($kept.Count). Saves were not touched."
