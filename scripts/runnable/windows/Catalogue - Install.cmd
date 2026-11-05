@echo off
rem Adds Catalogue to the ES-DE system carousel; the archive's folder and the rest
rem are chosen in the app. Downloads nothing, asks nothing and closes by itself. Runs
rem with Windows PowerShell, which comes with Windows.
echo Installing Catalogue for Atelier...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\catalogue\scripts\windows\setup.ps1"
echo.
timeout /t 20
