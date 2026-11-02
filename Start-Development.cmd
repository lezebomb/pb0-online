@echo off
cd /d "%~dp0"
if not exist "%~dp0game-instances\host\pb0-test-profile.json" (
  echo Prepare the isolated test profile first.
  pause
  exit /b 1
)
"%~dp0dist\PB0\PB0.exe" menu --game-root "%~dp0game-instances\host"
pause
