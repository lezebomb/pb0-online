@echo off
cd /d "%~dp0"
pwsh.exe -NoLogo -NoProfile -File "%~dp0scripts\run-pvp-prototype.ps1" -Dual
pause
