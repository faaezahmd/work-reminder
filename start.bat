@echo off
rem Starts Work Reminder in the background with a tray icon (no window stays open).
rem Optional: start.bat 45   (remind every 45 minutes)
if not "%~1"=="" > "%~dp0config.txt" echo %~1
start "" conhost.exe --headless powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scheduler.ps1"
