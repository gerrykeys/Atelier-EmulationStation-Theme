@echo off
rem Removes RetroAchievements from the ES-DE system carousel, the achievement progress
rem images (putting the physical media images back), and the username, Web API key and
rem cache saved by "Retro Achievements - Install". Runs with Windows PowerShell.
choice /m "Uninstall Retro Achievements and its settings from ES-DE"
if errorlevel 2 exit /b 0
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\achievements\scripts\windows\remove.ps1"
echo.
pause
