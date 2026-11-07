@echo off
rem Change how often the reminder pops up.
rem Double-click and type a number, or run: set-frequency.bat 45
title Work Reminder - set frequency
set "m=%~1"
if "%m%"=="" set /p "m=Remind me every how many minutes (1-480)? "
set "cfg=%~dp0config.txt"
powershell -NoProfile -Command "$v = 0; if ([int]::TryParse($env:m, [ref]$v) -and $v -ge 1 -and $v -le 480) { Set-Content -Path $env:cfg -Value $v; Write-Host ('Done. Reminder every ' + $v + ' min, counting from now.') } else { Write-Host 'Please use a whole number from 1 to 480.' }"
timeout /t 4 >nul
