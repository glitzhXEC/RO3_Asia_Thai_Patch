@echo off
setlocal
chcp 65001 > nul
pushd "%~dp0"

echo ========================================================
echo   RO3 Asia Japanese Translation Builder
echo ========================================================
echo.
py "import_translations.py"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo [ERROR] Translation build failed. Check the error above.
) else (
    echo [OK] Translation dictionaries were regenerated in this repository.
    echo      Use ..\Build-And-Deploy.bat to also copy them into the installed game.
)

popd
exit /b %RC%
