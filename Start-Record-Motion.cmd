@echo off
cd /d "%~dp0"
pwsh -NoLogo -NoProfile -File "%~dp0scripts\recording\record-motion.ps1"
