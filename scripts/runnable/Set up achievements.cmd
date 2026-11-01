@echo off
rem Saves the RetroAchievements username and Web API key used by the achievements app,
rem after checking them with the site, and adds RetroAchievements to the ES-DE system
rem carousel. The key is on retroachievements.org, under Settings, Keys. Needs Node.js.
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is required to run this script: https://nodejs.org
  echo.
  pause
  exit /b 1
)
echo Setting up RetroAchievements for Atelier...
echo.
node "%~dp0..\..\achievements\setup.js"
echo.
pause
