@echo off
rem Creates or updates one ES-DE collection for each release year of the games,
rem and the covers with a platform banner shown in the Collections system.
rem Close ES-DE before running it. Needs Node.js.
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is required to run this script: https://nodejs.org
  echo.
  pause
  exit /b 1
)
rem The image library for the banners is installed in the scripts folder the first time
if not exist "%~dp0..\node_modules\@resvg\resvg-js" (
  echo Installing the image library for the platform banners, once...
  call npm install --prefix "%~dp0.." --omit=dev --no-audit --no-fund --loglevel=error
  echo.
)
echo Updating the ES-DE year collections...
echo.
node "%~dp0..\year-collections.js"
echo.
pause
