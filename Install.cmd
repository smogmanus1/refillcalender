@echo off
rem ==========================================================================
rem  Install.cmd - double-click to install RefillCalendar
rem  Runs Install.ps1 next to it. No administrator rights needed.
rem  Part of RefillCalendar (MIT) - Brad Schrunk & Claude (Anthropic)
rem ==========================================================================
setlocal
title Install RefillCalendar
if not exist "%~dp0Install.ps1" (
    echo Can't find Install.ps1 next to this file. Keep the downloaded folder together
    echo - unzip the whole ZIP first, then double-click Install.cmd again.
    echo.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo The install did not finish (code %RC%). Scroll up for the reason.
pause
exit /b %RC%
