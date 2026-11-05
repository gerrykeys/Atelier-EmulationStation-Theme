@echo off
rem Shows your RetroAchievements progress in the ES-DE game details, as a small bar
rem drawn for every game with achievements. The achievements app keeps it up to date
rem each time it opens. Run "Retro Achievements - Install" first. Runs with Windows PowerShell.
echo Enabling the Retro Achievements progress bar in ES-DE...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\achievements\scripts\windows\progress.ps1"
echo.
pause
