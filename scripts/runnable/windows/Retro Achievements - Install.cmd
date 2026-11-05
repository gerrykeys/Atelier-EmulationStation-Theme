@echo off
rem Adds RetroAchievements to the ES-DE system carousel. The app signs in the first time
rem it opens, with RetroArch's username and the Web API key entered there (on
rem retroachievements.org, under Settings, Keys). Asks nothing and closes by itself.
rem Runs with Windows PowerShell, which comes with Windows.
echo Installing Retro Achievements for Atelier...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\achievements\scripts\windows\setup.ps1"
echo.
timeout /t 20
