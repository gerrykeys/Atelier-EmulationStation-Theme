@echo off
rem Removes the year collections and platform banners created by "Update year collections",
rem and puts the original miximages back.
rem Close ES-DE before running it. Needs Node.js.
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is required to run this script: https://nodejs.org
  echo.
  pause
  exit /b 1
)
echo Removing the ES-DE year collections...
echo.
node "%~dp0..\year-collections.js" --remove
echo.
pause
