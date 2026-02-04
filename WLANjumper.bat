@echo off
title WLAN Jumper Professional - Launcher
color 0B

:: 1. AUTO-ADMIN CHECK
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Requesting administrative privileges...
    powershell -Command "Start-Process -FilePath '%0' -Verb RunAs"
    exit /b
)

:: 2. PATH FIX & DIRECTORY SETUP
cd /d "%~dp0"
if not exist "Logs" mkdir "Logs"

echo ============================================================
echo                 WLAN JUMPER IS LOADING...
echo ============================================================
echo.

:: 3. SMART SEARCH & EXECUTE
set "FILENAME=WLAN-Waechter.ps1"

if exist "%~dp0%FILENAME%" (
    set "FINAL_PATH=%~dp0%FILENAME%"
) else (
    echo [!] Script not found in root. Searching recursively...
    for /r "%USERPROFILE%" %%F in (*) do (
        if "%%~nxF"=="%FILENAME%" (
            set "FINAL_PATH=%%~fF"
            goto :launch
        )
    )
)

:launch
if defined FINAL_PATH (
    :: Starts PowerShell in the current window (no hidden window)
    powershell -NoProfile -ExecutionPolicy Bypass -File "%FINAL_PATH%"
) else (
    echo [ERROR] %FILENAME% not found! Please place it in the same folder.
    pause
)
