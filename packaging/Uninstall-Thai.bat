@echo off
setlocal EnableExtensions
title RO3 Asia Thai Patch Uninstaller

set "BASE=%~dp0"
set "TARGET="
set "NO_PAUSE="
set "MARKER_NAME=.ro3-thai-patch-install.txt"
set "BEPINEX_PREEXISTING="

if /I "%~2"=="--no-pause" set "NO_PAUSE=1"

if not "%~1"=="" (
    if /I "%~nx1"=="ro3.exe" (
        set "TARGET=%~dp1"
    ) else (
        set "TARGET=%~f1"
    )
)

if not defined TARGET if exist "%BASE%ro3.exe" set "TARGET=%BASE%"

if not defined TARGET (
    echo.
    echo Enter the RO3 game folder that contains ro3.exe.
    echo You can also close this window and drag ro3.exe or its folder onto this BAT file.
    echo.
    set /p "TARGET=> "
)

set "TARGET=%TARGET:"=%"
if "%TARGET:~-1%"=="\" set "TARGET=%TARGET:~0,-1%"

if not exist "%TARGET%\ro3.exe" (
    echo.
    echo [ERROR] ro3.exe was not found in:
    echo "%TARGET%"
    echo.
    if not defined NO_PAUSE pause
    exit /b 1
)

if not exist "%TARGET%\%MARKER_NAME%" (
    echo.
    echo [ERROR] Installation record was not found.
    echo Automatic uninstall was stopped to avoid removing an existing BepInEx installation.
    echo.
    if not defined NO_PAUSE pause
    exit /b 2
)

for /f "tokens=1,2 delims==" %%A in ('findstr /B /C:"BEPINEX_PREEXISTING=" "%TARGET%\%MARKER_NAME%"') do set "BEPINEX_PREEXISTING=%%B"

if not "%BEPINEX_PREEXISTING%"=="0" (
    echo.
    echo [ERROR] BepInEx existed before this Thai patch was installed.
    echo This uninstaller will not remove that shared BepInEx environment automatically.
    echo.
    if not defined NO_PAUSE pause
    exit /b 3
)

echo.
echo Removing Thai patch from:
echo "%TARGET%"
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%Restore-Recovery.ps1" -GameClient "%TARGET%"
if errorlevel 1 (
    echo.
    echo [ERROR] Recovery localization restore failed. Uninstall was stopped before removing patch files.
    echo.
    if not defined NO_PAUSE pause
    exit /b 4
)

if exist "%TARGET%\BepInEx" rmdir /S /Q "%TARGET%\BepInEx"
if exist "%TARGET%\winhttp.dll" del /F /Q "%TARGET%\winhttp.dll"
if exist "%TARGET%\doorstop_config.ini" del /F /Q "%TARGET%\doorstop_config.ini"
if exist "%TARGET%\.doorstop_version" del /F /Q "%TARGET%\.doorstop_version"
if exist "%TARGET%\arialuni_sdf_u2022" del /F /Q "%TARGET%\arialuni_sdf_u2022"
if exist "%TARGET%\%MARKER_NAME%" del /F /Q "%TARGET%\%MARKER_NAME%"

echo.
echo [OK] Thai patch removed.
echo RO3 Recovery localization files were restored when the patch had modified them.
echo.
if not defined NO_PAUSE pause
exit /b 0
