@echo off
rem Stops the background Work Reminder.
title Work Reminder - stop
set "here=%~dp0"
powershell -NoProfile -Command "$target = Join-Path $env:here 'scheduler.ps1'; $procs = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.ProcessId -ne $PID -and $_.CommandLine -like ('*' + $target + '*') }); $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; if ($procs.Count) { Write-Host 'Work Reminder stopped.' } else { Write-Host 'Work Reminder was not running.' }"
timeout /t 3 >nul
