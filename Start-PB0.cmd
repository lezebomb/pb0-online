@echo off
cd /d "%~dp0"
if exist "%~dp0PB0.exe" (
  "%~dp0PB0.exe" %*
) else if exist "%~dp0dist\PB0\PB0.exe" (
  "%~dp0dist\PB0\PB0.exe" %*
) else (
  echo Run scripts\setup.ps1 first.
)
pause
