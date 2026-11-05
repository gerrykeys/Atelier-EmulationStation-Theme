@echo off
rem Removes the achievement progress images from the ES-DE game details and puts back
rem the physical media images they replaced. Runs with Windows PowerShell.
echo Disabling the Retro Achievements progress bar in ES-DE...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\achievements\scripts\windows\progress.ps1" --off
echo.
pause
