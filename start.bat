@echo off

:: This script ensures administrator privileges and then runs the main installer script.

:: Section 1: Request Administrator privileges
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Section 2: Execute the main PowerShell installer
echo Administrative privileges confirmed.
echo Launching installer...
powershell -ExecutionPolicy Bypass -File "%~dp0installing.ps1"

echo.
echo Script finished.
pause