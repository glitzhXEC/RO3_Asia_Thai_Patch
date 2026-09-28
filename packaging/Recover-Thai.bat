@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "TARGET=%~1"
set "NO_PAUSE="
set "REPAIR_OPTION="
set "CONFIRM_REPAIR="
if /I "%~2"=="--no-pause" set "NO_PAUSE=1"
if /I "%~3"=="--no-pause" set "NO_PAUSE=1"
if /I "%~2"=="--after-repair" set "REPAIR_OPTION=-AfterOfficialRepair"
if /I "%~3"=="--after-repair" set "REPAIR_OPTION=-AfterOfficialRepair"
if /I "%~nx1"=="ro3.exe" set "TARGET=%~dp1"
if not defined TARGET if exist "%~dp0ro3.exe" set "TARGET=%~dp0"
if not defined TARGET (
    echo Close RO3 and RO3AsiaLauncher. Enter the Client folder containing ro3.exe:
    set /p "TARGET=> "
)
set "TARGET=%TARGET:"=%"
if "%TARGET:~-1%"=="\" set "TARGET=%TARGET:~0,-1%"
echo "%TARGET%"
if defined REPAIR_OPTION (
    echo Use this mode ONLY after official launcher Repair completed and the game started successfully.
    echo Close the game and launcher. Old backups will be archived outside Client.
    echo Type REPAIRED to confirm, or press Enter to cancel.
    set /p "CONFIRM_REPAIR=> "
)
if defined REPAIR_OPTION if /I not "%CONFIRM_REPAIR%"=="REPAIRED" (
    echo [CANCELLED] No recovery changes made.
    if not defined NO_PAUSE pause
    exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-Recovery.ps1" -GameClient "%TARGET%" %REPAIR_OPTION%
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo [ERROR] Recovery stopped. Read the error above.
if "%RC%"=="0" echo [OK] Recovery complete. To enable Thai again, run Install-Thai.bat. Launch via RO3AsiaLauncher.
if not defined NO_PAUSE pause
exit /b %RC%
