#requires -Version 7.0
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$run=(Get-Content -Raw (Join-Path $project 'runs\dual-game-current.json') | ConvertFrom-Json).run
if(!$run.StartsWith((Join-Path $project 'runs\locomotion-game-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Not current locomotion session'}
$receipt=Get-Content -Raw (Join-Path $run 'locomotion-baseline-ready.json') | ConvertFrom-Json
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PB0TestWindowLabel {
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr p,string text,uint flags,uint timeout,out UIntPtr result);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern int GetWindowText(IntPtr h,StringBuilder text,int max);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern int GetClassName(IntPtr h,StringBuilder text,int max);
}
"@
foreach($role in @('host','guest')){
 $expected=Join-Path $project ('game-instances\'+$role+'\platform\steam\PBZ.exe')
 $gameId=$receipt.players.$role
 $process=Get-CimInstance Win32_Process -Filter "ProcessId=$gameId"
 if(!$process -or $process.ExecutablePath -ne $expected){throw 'Refusing to label an unrelated process'}
 $handle=(Get-Process -Id $gameId).MainWindowHandle
 $class=[Text.StringBuilder]::new(256)
 [void][PB0TestWindowLabel]::GetClassName($handle,$class,256)
 if($handle -eq [IntPtr]::Zero -or $class.ToString() -ne 'UnrealWindow'){throw 'No owned Unreal game window'}
 $title=if($role -eq 'host'){'PB0 Host - Remote View'}else{'PB0 Guest - Local View'}
 $answer=[UIntPtr]::Zero
 $sent=[PB0TestWindowLabel]::SendMessageTimeout($handle,0x000C,[UIntPtr]::Zero,$title,2,1000,[ref]$answer)
 if($sent -eq [IntPtr]::Zero){throw 'Game window did not respond to its test label'}
 $actual=[Text.StringBuilder]::new(256);[void][PB0TestWindowLabel]::GetWindowText($handle,$actual,256)
 if($actual.ToString() -ne $title){throw 'Game did not retain capture label'}
 [pscustomobject]@{Role=$role;Pid=$gameId;Title=$title;WindowClass=$class.ToString()}
}