@echo off
setlocal EnableExtensions
title RO3 Asia Thai Patch Installer

set "BASE=%~dp0"
set "PAYLOAD=%BASE%payload"
set "TARGET="
set "NO_PAUSE="
set "MARKER_NAME=.ro3-thai-patch-install.txt"
set "BEPINEX_PREEXISTING="
set "PATCH_VERSION=unknown"
set "UPDATE_MODE="

if /I "%~2"=="--no-pause" set "NO_PAUSE=1"
if exist "%BASE%VERSION.txt" set /p PATCH_VERSION=<"%BASE%VERSION.txt"

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

if not exist "%PAYLOAD%\winhttp.dll" (
    echo.
    echo [ERROR] The payload folder is incomplete.
    echo Re-extract the ZIP and try again.
    echo.
    if not defined NO_PAUSE pause
    exit /b 2
)

if exist "%TARGET%\%MARKER_NAME%" (
    set "UPDATE_MODE=1"
    for /f "tokens=1,2 delims==" %%A in ('findstr /B /C:"BEPINEX_PREEXISTING=" "%TARGET%\%MARKER_NAME%"') do set "BEPINEX_PREEXISTING=%%B"
)

if not defined BEPINEX_PREEXISTING (
    if exist "%TARGET%\BepInEx" (
        set "BEPINEX_PREEXISTING=1"
    ) else (
        set "BEPINEX_PREEXISTING=0"
    )
)

echo.
if defined UPDATE_MODE (
    echo Updating Thai patch to version %PATCH_VERSION% in:
) else (
    echo Installing Thai patch version %PATCH_VERSION% to:
)
echo "%TARGET%"
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%Restore-Recovery.ps1" -GameClient "%TARGET%"
if errorlevel 1 (
    echo [ERROR] Recovery preparation failed. Installation stopped.
    if not defined NO_PAUSE pause
    exit /b 4
)

rem Robocopy overwrites same-name files, so installing over a previous patch is supported.
robocopy "%PAYLOAD%" "%TARGET%" /E /COPY:DAT /DCOPY:T /R:1 /W:1 /NP /NFL /NDL /NJH /NJS
set "COPY_RC=%ERRORLEVEL%"

if %COPY_RC% GEQ 8 (
    echo.
    echo [ERROR] File copy failed. Robocopy exit code: %COPY_RC%
    echo.
    if not defined NO_PAUSE pause
    exit /b %COPY_RC%
)

>"%TARGET%\%MARKER_NAME%" echo RO3_THAI_PATCH=1
>>"%TARGET%\%MARKER_NAME%" echo PATCH_VERSION=%PATCH_VERSION%
>>"%TARGET%\%MARKER_NAME%" echo BEPINEX_PREEXISTING=%BEPINEX_PREEXISTING%

echo.
if defined UPDATE_MODE (
    echo [OK] Thai patch updated to %PATCH_VERSION%.
) else (
    echo [OK] Thai patch installed: %PATCH_VERSION%.
)
echo Launch RO3 through RO3AsiaLauncher, not ro3.exe directly.
echo.
if not defined NO_PAUSE pause
exit /b 0
