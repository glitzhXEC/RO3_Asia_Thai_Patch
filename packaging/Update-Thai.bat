@echo off
setlocal EnableExtensions
title RO3 Asia Thai Patch Updater

set "BASE=%~dp0"
set "TARGET=%~1"
set "NO_PAUSE="
set "LOCAL_UPDATE="

if /I "%~1"=="--local" (
    set "LOCAL_UPDATE=1"
    set "TARGET=%~2"
    if /I "%~3"=="--no-pause" set "NO_PAUSE=1"
) else (
    if /I "%~2"=="--local" set "LOCAL_UPDATE=1"
    if /I "%~2"=="--no-pause" set "NO_PAUSE=1"
    if /I "%~3"=="--no-pause" set "NO_PAUSE=1"
)

if defined LOCAL_UPDATE (
    if not exist "%BASE%Install-Thai.bat" (
        echo.
        echo [ERROR] Install-Thai.bat was not found next to this BAT file.
        echo Re-extract the release ZIP and try again.
        echo.
        if not defined NO_PAUSE pause
        exit /b 2
    )

    call "%BASE%Install-Thai.bat" "%TARGET%" --no-pause
    set "RC=%ERRORLEVEL%"
) else (
    if not exist "%BASE%Update-Latest.ps1" (
        echo.
        echo [ERROR] Update-Latest.ps1 was not found next to this BAT file.
        echo Re-extract the release ZIP and try again.
        echo.
        if not defined NO_PAUSE pause
        exit /b 2
    )

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%Update-Latest.ps1" -GameTarget "%TARGET%"
    set "RC=%ERRORLEVEL%"
)

echo.
if %RC% EQU 0 (
    if defined LOCAL_UPDATE (
        echo [OK] Local update completed.
    ) else (
        echo [OK] Update check/install completed.
    )
) else (
    echo [ERROR] Update failed. Exit code: %RC%
)
echo.

if not defined NO_PAUSE pause
exit /b %RC%
