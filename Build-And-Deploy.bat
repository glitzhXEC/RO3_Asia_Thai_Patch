@echo off
setlocal
chcp 65001 > nul
pushd "%~dp0"

py -3 "scripts\validate-thai-payload.py"
if errorlevel 1 (
    set "RC=%ERRORLEVEL%"
    echo.
    echo [ERROR] Thai payload validation failed. Deployment was not attempted.
    popd
    exit /b %RC%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Build-LocalizationTablePatcher.ps1"
if errorlevel 1 (
    set "RC=%ERRORLEVEL%"
    echo.
    echo [ERROR] Localization-table patcher build failed. Deployment was not attempted.
    popd
    exit /b %RC%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\Deploy-To-Game.ps1"
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
