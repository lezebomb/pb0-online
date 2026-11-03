param([Parameter(Mandatory)][string]$Run)
$ErrorActionPreference='Stop'
$root='D:\pb0online\runs\locomotion-game-'
if(!$Run.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Not an owned session'}
$receipt=Get-Content -Raw -LiteralPath (Join-Path $Run 'locomotion-record-ready.json') | ConvertFrom-Json
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PB0ForegroundReadOnly {
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint id);
}
"@
$out=[IO.StreamWriter]::new((Join-Path $Run 'window-foreground.csv'),$false,[Text.UTF8Encoding]::new($false))
$out.WriteLine('unixMs,hostForeground,guestForeground')
$deadline=(Get-Date).AddSeconds(40)
try{
 while((Get-Date) -lt $deadline -and !(Test-Path -LiteralPath (Join-Path $Run 'locomotion-recorder-done')) -and !(Test-Path -LiteralPath (Join-Path $Run 'stop'))){
  $windowProcess=[uint32]0
  [void][PB0ForegroundReadOnly]::GetWindowThreadProcessId([PB0ForegroundReadOnly]::GetForegroundWindow(),[ref]$windowProcess)
  $out.WriteLine(('{0},{1},{2}' -f [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(),[int]($windowProcess -eq $receipt.hostPid),[int]($windowProcess -eq $receipt.guestPid)))
  $out.Flush()
  Start-Sleep -Milliseconds 200
 }
}finally{$out.Dispose()}
