@echo off
REM =====================================================================
REM  Serve the built APK over your local network so the phone can
REM  download it directly from a browser. Press Ctrl+C to stop.
REM =====================================================================

cd /d "%~dp0"

echo.
echo First run may trigger a Windows Firewall prompt - choose "Allow".
echo.

node "serve-apk.js"

if errorlevel 1 (
    echo.
    echo Failed to start. Make sure Node.js is installed and on PATH.
    pause
)
