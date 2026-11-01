@echo off
rem Removes the achievement progress images from the ES-DE game details and puts back
rem the physical media images they replaced. Needs Node.js.
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is required to run this script: https://nodejs.org
  echo.
  pause
  exit /b 1
)
echo Removing the achievement progress from ES-DE...
echo.
node "%~dp0..\..\achievements\progress.js" --off
echo.
pause
