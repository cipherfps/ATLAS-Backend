@echo off
setlocal enabledelayedexpansion
title ATLAS Setup
color 0A

echo ========================================
echo    ATLAS - First Time Setup
echo ========================================
echo.

REM Check if Bun is installed
echo [1/3] Checking for Bun installation...
where bun >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Bun is already installed!
    for /f "tokens=*" %%i in ('bun --version 2^>nul') do set BUN_VERSION=%%i
    echo [OK] Bun version: !BUN_VERSION!
    goto :install_deps
)

echo [!] Bun is not installed.
echo.
echo Bun is required to run ATLAS. Would you like to install it now?
echo.
echo Options:
echo   1. Install Bun automatically (Recommended)
echo   2. Open Bun website to install manually
echo   3. Exit setup
echo.
set /p choice="Enter your choice (1-3): "

if "%choice%"=="1" goto :auto_install
if "%choice%"=="2" goto :manual_install
if "%choice%"=="3" goto :exit
echo Invalid choice. Exiting...
goto :exit

:auto_install
echo.
echo [*] Downloading and installing Bun...
echo [*] This may take a moment...
powershell -Command "& {irm bun.sh/install.ps1 | iex}"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to install Bun automatically.
    echo [*] Please visit https://bun.sh to install manually.
    pause
    goto :exit
)

REM Refresh environment variables
echo [*] Refreshing environment...
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%b"
set "PATH=%USER_PATH%;%PATH%"

REM Check if Bun is now available
where bun >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Bun was installed but not found in PATH.
    echo [*] Please restart your terminal and run this script again.
    pause
    goto :exit
)

echo [OK] Bun installed successfully!
for /f "tokens=*" %%i in ('bun --version 2^>nul') do set BUN_VERSION=%%i
echo [OK] Bun version: !BUN_VERSION!
goto :install_deps

:manual_install
echo.
echo [*] Opening Bun installation page...
start https://bun.sh/docs/installation
echo.
echo Please install Bun and run this setup script again.
pause
goto :exit

:install_deps
echo.
echo [2/3] Installing project dependencies...
bun install
if %errorlevel% neq 0 (
    echo [ERROR] Failed to install dependencies.
    echo [*] Please check your internet connection and try again.
    pause
    goto :exit
)
echo [OK] Dependencies installed successfully!

:verify
echo.
echo [3/3] Verifying installation...
if not exist "node_modules\" (
    echo [ERROR] node_modules folder not found.
    echo [*] Dependencies may not have been installed correctly.
    pause
    goto :exit
)

if not exist "src\index.ts" (
    echo [ERROR] Main application file not found.
    echo [*] Project structure may be incomplete.
    pause
    goto :exit
)

echo [OK] Installation verified!
echo.
echo ========================================
echo    Setup Complete!
echo ========================================
echo.
echo To start ATLAS, run: start.bat
echo.
echo For support, join the Discord:
echo https://discord.gg/G9MAF77V7R
echo.
pause
goto :exit

:exit
endlocal
