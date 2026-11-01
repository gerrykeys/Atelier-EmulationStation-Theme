@echo off
rem Removes RetroAchievements from the ES-DE system carousel, the achievement progress
rem images (putting the physical media images back), and the username, Web API key and
rem cache saved by "Set up achievements". Needs Node.js.
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is required to run this script: https://nodejs.org
  echo.
  pause
  exit /b 1
)
choice /m "Remove RetroAchievements and its settings from ES-DE"
if errorlevel 2 exit /b 0
echo.
node "%~dp0..\..\achievements\remove.js"
echo.
pause
