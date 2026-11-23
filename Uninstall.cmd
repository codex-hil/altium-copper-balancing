@echo off
setlocal
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Action Uninstall -Interactive
if errorlevel 1 pause
