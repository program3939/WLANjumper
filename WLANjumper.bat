@echo off
title WLAN Jumper Professional
color 0B

:: 1. AUTO-ADMIN: Fragt nach Admin-Rechten, wenn nicht vorhanden
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process -FilePath '%0' -Verb RunAs"
    exit /b
)

:: 2. PFAD-FIX: Setzt den Fokus direkt auf den Ordner der Batch
cd /d "%~dp0"

echo ============================================================
echo                WLAN JUMPER IS NOW ACTIVE
echo ============================================================
echo.

:: 3. SMART SEARCH & EXECUTE
set "FILENAME=WLAN-Waechter.ps1"

if exist "%~dp0%FILENAME%" (
    set "FINAL_PATH=%~dp0%FILENAME%"
) else (
    echo [!] Searching for %FILENAME%...
    for /r "%USERPROFILE%" %%F in (*) do (
        if "%%~nxF"=="%FILENAME%" (
            set "FINAL_PATH=%%~fF"
            goto :launch
        )
    )
)

:launch
if defined FINAL_PATH (
    :: Startet PowerShell versteckt oder im Vordergrund, exakt wie die EXE
    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%FINAL_PATH%"
) else (
    echo [ERROR] Script not found! Please keep WLAN-Waechter.ps1 on your PC.
    pause
)