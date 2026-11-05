@echo off
rem Takes Catalogue out of the ES-DE system carousel, takes its collections out of ES-DE
rem and removes its settings. Close ES-DE first if you made collections. Your archives,
rem their collections, your games and saves stay as they are. Runs with Windows PowerShell.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\catalogue\scripts\windows\remove.ps1"
echo.
pause
