@echo off
rem Shows your RetroAchievements progress in the ES-DE game details, as a small bar
rem drawn for every game with achievements. The achievements app keeps it up to date
rem each time it opens. Run "Set up achievements" first. Needs Node.js.
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is required to run this script: https://nodejs.org
  echo.
  pause
  exit /b 1
)
rem The image library is installed in the scripts folder the first time
if not exist "%~dp0..\node_modules\@resvg\resvg-js" (
  echo Installing the image library for the progress bars, once...
  call npm install --prefix "%~dp0.." --omit=dev --no-audit --no-fund --loglevel=error
  echo.
)
echo Drawing the achievement progress for ES-DE...
echo.
node "%~dp0..\..\achievements\progress.js"
echo.
pause
