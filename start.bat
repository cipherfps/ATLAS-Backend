@echo off
title ATLAS

REM Check if Bun is installed
where bun >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Bun is not installed!
    echo.
    echo Please run install_packages.bat first to install Bun and dependencies.
    echo.
    pause
    exit /b 1
)

REM Check if dependencies are installed
if not exist "node_modules\" (
    echo [*] Installing dependencies...
    bun install
    if %errorlevel% neq 0 (
        echo [ERROR] Failed to install dependencies.
        pause
        exit /b %errorlevel%
    )
)

echo Starting ATLAS...
echo.
bun run src/index.ts
