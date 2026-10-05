@echo off
REM =====================================================================
REM  Enable Windows Developer Mode.
REM  Flutter needs symlink support to build projects with plugins.
REM  Double-click this file and approve the UAC prompt.
REM =====================================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set KEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock

echo Enabling Developer Mode...
reg add "%KEY%" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1

echo.
echo ===================================================
echo  Current setting (1 = enabled):
reg query "%KEY%" /v AllowDevelopmentWithoutDevLicense
echo ===================================================
echo.
echo Done. You can close this window.
pause
