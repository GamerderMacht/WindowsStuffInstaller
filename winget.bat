@echo off
setlocal

:: Check if winget is available
where winget >nul 2>&1
if %errorlevel%==0 (
    echo Winget is already installed.
) else (
    echo Winget is not installed. Installing Winget...

    :: Check if running as administrator
    net session >nul 2>&1
    if %errorlevel% NEQ 0 (
        echo This script needs to be run as administrator.
        pause
        exit /b
    )

    :: Install Winget via App Installer from Microsoft Store
    powershell -Command "Start-Process ms-windows-store://pdp/?productid=9NBLGGH4NNS1"

    echo Please install "App Installer" from the Microsoft Store, then press any key to continue...
    pause
)

echo.
echo Script finished.
pause
