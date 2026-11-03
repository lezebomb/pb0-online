#requires -Version 7.0
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$locator="${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs=if(Test-Path -LiteralPath $locator){& $locator -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath}
$output=Join-Path $project 'runs\motion-clock-build'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$source=Join-Path $project 'src\Pb0.Mod\Native\clock.cpp'
if(!$vs){
 $zig=Join-Path $project 'tools\zig-python\ziglang\zig.exe'
 if(!(Test-Path -LiteralPath $zig)){throw 'Visual Studio C++ tools or project-local portable Zig required'}
 $env:ZIG_GLOBAL_CACHE_DIR=Join-Path $output 'cache'
 & $zig c++ -target x86_64-windows-gnu -shared -O2 -fno-exceptions -fno-rtti -fno-threadsafe-statics -nostdlib++ $source -o (Join-Path $output 'PB0Clock.dll')
 if($LASTEXITCODE -ne 0){throw 'Motion clock build failed'}
 return
}
$vcvars=Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$batch=Join-Path $output 'build.cmd'
@"
@echo off
call "$vcvars" >nul 2>nul
cd /d "$output"
cl /nologo /std:c++20 /O2 /MT /EHsc /W4 /LD "$source" /Fe:PB0Clock.dll /link /NOLOGO
"@ | Set-Content -LiteralPath $batch -Encoding ascii
& cmd /c $batch
if($LASTEXITCODE -ne 0){throw 'Motion clock build failed'}
